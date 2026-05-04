"""GardNx Backend — AI-powered garden planning API.

Production-grade FastAPI application with:
- Proper dependency injection (no global mutable state)
- Structured logging (JSON in prod, human-readable in dev)
- Request ID tracking & timing middleware
- Security headers on every response
- Global exception handling with clean JSON error responses
- Configurable CORS based on environment
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.config import settings
from app.errors import GardNxError
from app.logging_config import setup_logging
from app.middleware import RequestIdMiddleware, SecurityHeadersMiddleware
from app.services.garden_analyzer import GardenAnalyzer

logger = logging.getLogger("gardnx")


# ── Startup / shutdown ────────────────────────────────────────────────────


def _init_firebase() -> None:
    """Initialize Firebase Admin SDK if credentials are available."""
    try:
        import firebase_admin
        from firebase_admin import credentials

        if firebase_admin._apps:
            logger.info("Firebase already initialized")
            return

        creds_path = settings.firebase_creds_path
        if creds_path.exists():
            cred = credentials.Certificate(str(creds_path))
            firebase_admin.initialize_app(
                cred,
                {"storageBucket": settings.firebase_storage_bucket},
            )
            logger.info("Firebase initialized successfully")
        else:
            logger.warning(
                "Firebase credentials not found at %s. "
                "Firebase features will be unavailable.",
                creds_path,
            )
    except Exception as e:
        logger.warning("Firebase initialization failed: %s", e)


def _load_analyzer() -> GardenAnalyzer:
    """Load the ML model or initialize mock mode and return the analyzer."""
    analyzer = GardenAnalyzer(
        weights_path=str(settings.weights_path),
        use_mock=settings.use_mock_model,
        hf_api_token=settings.hf_api_token,
    )
    analyzer.load_model()

    if settings.use_mock_model:
        logger.info("Garden analyzer initialized in MOCK mode")
    else:
        logger.info("Garden analyzer initialized with real model weights")

    return analyzer


def _log_startup_banner() -> None:
    """Log a clear summary of which services are available."""
    lines = [
        "",
        "┌──────────────────────────────────────────┐",
        "│         GardNx Backend v1.0.0            │",
        "├──────────────────────────────────────────┤",
        f"│  Debug mode:      {'ON' if settings.debug else 'OFF':>20s} │",
        f"│  Host:            {settings.host:>20s} │",
        f"│  Port:            {settings.port:>20d} │",
        f"│  Mock ML:         {'YES' if settings.use_mock_model else 'NO':>20s} │",
        f"│  Gemini API:      {'configured' if settings.gemini_api_key else 'not set':>20s} │",
        f"│  HuggingFace:     {'configured' if settings.hf_api_token else 'not set':>20s} │",
        f"│  Perenual:        {'configured' if settings.perenual_api_key else 'not set':>20s} │",
        f"│  Allow anon:      {'YES' if settings.allow_anon else 'NO':>20s} │",
        "└──────────────────────────────────────────┘",
        "",
    ]
    for line in lines:
        logger.info(line)


@asynccontextmanager
async def lifespan(application: FastAPI):
    """Startup and shutdown logic."""
    # Configure logging before anything else
    setup_logging(debug=settings.debug)

    logger.info("Starting GardNx Backend...")

    # Validate configuration
    settings.validate_on_startup()

    # Initialize Firebase
    _init_firebase()

    # Load ML model and store on app.state (not a global dict)
    application.state.analyzer = _load_analyzer()

    _log_startup_banner()
    yield

    # Cleanup
    logger.info("Shutting down GardNx Backend...")
    application.state.analyzer = None


# ── Application factory ──────────────────────────────────────────────────

app = FastAPI(
    title="GardNx API",
    description=(
        "AI-powered garden planning backend for Mauritius.\n\n"
        "Features: photo analysis, plant recommendations, layout generation, "
        "planting calendars, and climate data."
    ),
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs" if settings.debug else None,
    redoc_url="/redoc" if settings.debug else None,
)


# ── Middleware (order matters — outermost first) ──────────────────────────

app.add_middleware(RequestIdMiddleware)
app.add_middleware(SecurityHeadersMiddleware)

# CORS — strict in production, permissive in debug
if settings.debug:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,  # Can't use credentials with wildcard
        allow_methods=["*"],
        allow_headers=["*"],
    )
else:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins_list,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
    )


# ── Exception handlers ───────────────────────────────────────────────────


@app.exception_handler(GardNxError)
async def gardnx_error_handler(request: Request, exc: GardNxError) -> JSONResponse:
    """Handle all custom GardNx exceptions with clean JSON responses."""
    request_id = getattr(request.state, "request_id", "unknown")
    logger.warning(
        "GardNxError [%s]: %s %s → %d: %s",
        request_id,
        request.method,
        request.url.path,
        exc.status_code,
        exc.detail,
    )
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": exc.__class__.__name__,
            "detail": exc.detail,
            "request_id": request_id,
        },
    )


@app.exception_handler(RequestValidationError)
async def validation_error_handler(
    request: Request, exc: RequestValidationError
) -> JSONResponse:
    """Return clean 422 responses for Pydantic validation failures."""
    request_id = getattr(request.state, "request_id", "unknown")
    errors = []
    for err in exc.errors():
        field = " → ".join(str(loc) for loc in err.get("loc", []))
        errors.append({
            "field": field,
            "message": err.get("msg", "Validation error"),
            "type": err.get("type", "value_error"),
        })

    return JSONResponse(
        status_code=422,
        content={
            "error": "ValidationError",
            "detail": "Request validation failed.",
            "errors": errors,
            "request_id": request_id,
        },
    )


@app.exception_handler(Exception)
async def unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
    """Catch-all for unhandled exceptions — never leak stack traces in production."""
    request_id = getattr(request.state, "request_id", "unknown")
    logger.exception(
        "Unhandled exception [%s]: %s %s",
        request_id,
        request.method,
        request.url.path,
    )

    detail = str(exc) if settings.debug else "An internal error occurred."
    return JSONResponse(
        status_code=500,
        content={
            "error": "InternalServerError",
            "detail": detail,
            "request_id": request_id,
        },
    )


# ── Routes ────────────────────────────────────────────────────────────────

from app.api.v1.router import v1_router  # noqa: E402

app.include_router(v1_router, prefix="/api/v1")


@app.get("/health", tags=["health"])
async def health_check():
    """Basic health check — always returns 200 if the server is responding."""
    analyzer = getattr(app.state, "analyzer", None)
    return {
        "status": "ok",
        "version": "1.0.0",
        "model_loaded": analyzer is not None,
        "mock_mode": settings.use_mock_model,
    }


@app.get("/health/ready", tags=["health"])
async def readiness_check():
    """Readiness check — returns 200 only if all critical services are up.

    Use this for Kubernetes readiness probes or load balancer health checks.
    """
    issues = []

    # Check analyzer
    analyzer = getattr(app.state, "analyzer", None)
    if analyzer is None:
        issues.append("ML analyzer not loaded")

    # Check Firebase
    try:
        import firebase_admin

        if not firebase_admin._apps:
            issues.append("Firebase not initialized")
    except ImportError:
        issues.append("firebase_admin not installed")

    if issues:
        return JSONResponse(
            status_code=503,
            content={"status": "not_ready", "issues": issues},
        )

    return {"status": "ready"}


@app.get("/health/live", tags=["health"])
async def liveness_check():
    """Liveness check — always returns 200. Use for Kubernetes liveness probes."""
    return {"status": "alive"}


# ── Direct execution ─────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
    )
