"""Custom exception hierarchy for the GardNx backend.

All exceptions inherit from GardNxError and map to specific HTTP status codes.
The global exception handler in main.py catches these and returns clean JSON responses.
"""

from typing import Any


class GardNxError(Exception):
    """Base exception for all GardNx application errors."""

    status_code: int = 500
    detail: str = "An internal error occurred."

    def __init__(self, detail: str | None = None, **extra: Any):
        self.detail = detail or self.__class__.detail
        self.extra = extra
        super().__init__(self.detail)


class NotFoundError(GardNxError):
    """Resource not found (404)."""

    status_code = 404
    detail = "The requested resource was not found."


class AuthorizationError(GardNxError):
    """Authentication or authorization failure (401)."""

    status_code = 401
    detail = "Unauthorized."


class ForbiddenError(GardNxError):
    """Action not permitted (403)."""

    status_code = 403
    detail = "You do not have permission to perform this action."


class BadRequestError(GardNxError):
    """Client sent an invalid request (400)."""

    status_code = 400
    detail = "Bad request."


class RateLimitError(GardNxError):
    """Client exceeded rate limit (429)."""

    status_code = 429
    detail = "Too many requests. Please slow down."


class ExternalServiceError(GardNxError):
    """An external service (Gemini, HuggingFace, Perenual, Open-Meteo) failed (502)."""

    status_code = 502
    detail = "An external service is temporarily unavailable."


class ModelNotLoadedError(GardNxError):
    """ML model is not yet available (503)."""

    status_code = 503
    detail = "Model not loaded yet. Please try again shortly."


class ConfigurationError(GardNxError):
    """Application misconfiguration (500, but logged as critical)."""

    status_code = 500
    detail = "Server configuration error."
