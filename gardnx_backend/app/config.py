"""Application configuration using pydantic-settings."""

import os
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings


def _default_use_mock() -> bool:
    """Mock only when HF_API_TOKEN is missing — otherwise run real segmentation."""
    return not bool(os.getenv("HF_API_TOKEN", "").strip())


class Settings(BaseSettings):
    """Application settings loaded from environment variables and .env file."""

    firebase_credentials_path: str = "./firebase-credentials.json"
    firebase_storage_bucket: str = "gardnx-app.appspot.com"
    model_weights_path: str = "./app/ml/weights/deeplabv3_garden.pth"
    use_mock_model: bool = Field(default_factory=_default_use_mock)
    allow_anon: bool = False
    photo_storage_path: str = "./data/photos"
    host: str = "0.0.0.0"
    port: int = 8000
    debug: bool = True
    open_meteo_base_url: str = "https://archive-api.open-meteo.com/v1/archive"
    perenual_api_key: str = ""
    gemini_api_key: str = ""
    hf_api_token: str = ""
    ollama_url: str = "http://localhost:11434"
    ollama_model: str = "gemma3:1b"
    warm_ollama_on_startup: bool = False

    @property
    def weights_path(self) -> Path:
        return Path(self.model_weights_path)

    @property
    def firebase_creds_path(self) -> Path:
        return Path(self.firebase_credentials_path)

    model_config = {
        "env_file": ".env",
        "env_file_encoding": "utf-8",
        "case_sensitive": False,
        "protected_namespaces": ("settings_",),
    }


settings = Settings()
