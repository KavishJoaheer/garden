"""Centralized dependency injection container for the GardNx backend.

All service singletons are created once and injected via FastAPI's Depends()
system. This eliminates the scattered `global _variable` pattern and makes
testing trivial (just override the dependency).
"""

import logging
from functools import lru_cache

from app.config import settings
from app.errors import ModelNotLoadedError

logger = logging.getLogger("gardnx")


# ── Service factories (cached singletons) ────────────────────────────────


@lru_cache(maxsize=1)
def get_plant_recommender():
    """Return the singleton PlantRecommender (loaded from JSON catalog)."""
    from app.services.plant_recommender import PlantRecommender

    rec = PlantRecommender()
    logger.info("PlantRecommender loaded: %d plants", len(rec.plants))
    return rec


@lru_cache(maxsize=1)
def get_companion_checker():
    """Return the singleton CompanionChecker."""
    from app.services.companion_checker import CompanionChecker

    return CompanionChecker()


@lru_cache(maxsize=1)
def get_layout_generator():
    """Return the singleton LayoutGenerator."""
    from app.services.layout_generator import LayoutGenerator

    return LayoutGenerator()


@lru_cache(maxsize=1)
def get_gemini_recommender():
    """Return the singleton GeminiRecommender (may be unavailable)."""
    from app.services.gemini_recommender import GeminiRecommender

    return GeminiRecommender(api_key=settings.gemini_api_key)


@lru_cache(maxsize=1)
def get_ollama_recommender():
    """Return the singleton OllamaRecommender."""
    from app.services.ollama_recommender import OllamaRecommender

    return OllamaRecommender()


@lru_cache(maxsize=1)
def get_gemini_companion_checker():
    """Return the singleton GeminiCompanionChecker."""
    from app.services.gemini_companion_checker import GeminiCompanionChecker

    return GeminiCompanionChecker(api_key=settings.gemini_api_key)


@lru_cache(maxsize=1)
def get_perenual_service():
    """Return the singleton PerenualService."""
    from app.services.perenual_service import PerenualService

    return PerenualService(api_key=settings.perenual_api_key)


@lru_cache(maxsize=1)
def get_climate_service():
    """Return the singleton ClimateService."""
    from app.services.climate_service import ClimateService

    return ClimateService()


def get_analyzer():
    """Return the global GardenAnalyzer instance.

    Raises ModelNotLoadedError if the analyzer hasn't been initialized yet
    (startup still in progress).
    """
    from app.main import app

    analyzer = getattr(app.state, "analyzer", None)
    if analyzer is None:
        raise ModelNotLoadedError()
    return analyzer
