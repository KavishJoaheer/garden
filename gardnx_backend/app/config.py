"""Application configuration using pydantic-settings.

All values can be overridden via environment variables or a .env file.
Includes startup validation to catch misconfigurations early.
"""

import logging
import os
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings

logger = logging.getLogger("gardnx")


def _default_use_mock() -> bool:
    """Mock only when HF_API_TOKEN is missing — otherwise run real segmentation."""
    return not bool(os.getenv("HF_API_TOKEN", "").strip())


class Settings(BaseSettings):
    """Application settings loaded from environment variables and .env file."""

    # ── Firebase ──────────────────────────────────────────────────────────
    firebase_credentials_path: str = "./firebase-credentials.json"
    firebase_storage_bucket: str = "gardnx-app.appspot.com"

    # ── ML Model ──────────────────────────────────────────────────────────
    model_weights_path: str = "./app/ml/weights/deeplabv3_garden.pth"
    use_mock_model: bool = Field(default_factory=_default_use_mock)

    # ── Auth ──────────────────────────────────────────────────────────────
    allow_anon: bool = False

    # ── Storage ───────────────────────────────────────────────────────────
    photo_storage_path: str = "./data/photos"

    # ── Server ────────────────────────────────────────────────────────────
    host: str = "0.0.0.0"
    port: int = 8000
    debug: bool = True

    # ── CORS ──────────────────────────────────────────────────────────────
    allowed_origins: str = Field(
        default="http://localhost:3000,http://localhost:8080",
        description="Comma-separated list of allowed CORS origins (production only)",
    )

    # ── External APIs ─────────────────────────────────────────────────────
    open_meteo_base_url: str = "https://archive-api.open-meteo.com/v1/archive"
    perenual_api_key: str = ""
    gemini_api_key: str = ""
    hf_api_token: str = ""

    # ── Ollama (local LLM) ────────────────────────────────────────────────
    ollama_url: str = "http://localhost:11434"
    ollama_model: str = "gemma3:1b"
    warm_ollama_on_startup: bool = False

    # ── Derived properties ────────────────────────────────────────────────

    @property
    def weights_path(self) -> Path:
        return Path(self.model_weights_path)

    @property
    def firebase_creds_path(self) -> Path:
        return Path(self.firebase_credentials_path)

    @property
    def allowed_origins_list(self) -> list[str]:
        """Parse comma-separated origins string into a list."""
        return [o.strip() for o in self.allowed_origins.split(",") if o.strip()]

    # ── Startup validation ────────────────────────────────────────────────

    def validate_on_startup(self) -> None:
        """Validate configuration at startup and log warnings.

        This does NOT crash the server on non-critical issues — it just
        logs clear messages about what's misconfigured and what features
        will be unavailable.
        """
        issues: list[str] = []
        warnings: list[str] = []

        # Firebase credentials
        if not self.firebase_creds_path.exists():
            warnings.append(
                f"Firebase credentials not found at {self.firebase_credentials_path}. "
                "Auth and Firestore will be unavailable."
            )

        # Firebase storage bucket placeholder
        if self.firebase_storage_bucket in (
            "your-project-id.firebasestorage.app",
            "gardnx-app.appspot.com",
        ):
            warnings.append(
                "Firebase storage bucket is still set to the default placeholder. "
                "Photo uploads to Firebase Storage will fail."
            )

        # Anon mode in non-debug
        if self.allow_anon and not self.debug:
            issues.append(
                "ALLOW_ANON=true is enabled without DEBUG=true. "
                "This is a SECURITY RISK in production!"
            )

        # Optional API keys
        optional_services = {
            "Gemini (AI recommendations)": bool(self.gemini_api_key),
            "HuggingFace (real ML segmentation)": bool(self.hf_api_token),
            "Perenual (plant images/search)": bool(self.perenual_api_key),
        }
        unavailable = [name for name, avail in optional_services.items() if not avail]
        if unavailable:
            warnings.append(
                "Optional API keys not configured: "
                + ", ".join(unavailable)
                + ". These features will use fallbacks."
            )

        # Log results
        for issue in issues:
            logger.critical("CONFIG ISSUE: %s", issue)
        for warning in warnings:
            logger.warning("CONFIG: %s", warning)

        if not issues and not warnings:
            logger.info("Configuration validated: all settings OK")

    model_config = {
        "env_file": ".env",
        "env_file_encoding": "utf-8",
        "case_sensitive": False,
        "protected_namespaces": ("settings_",),
    }


settings = Settings()
