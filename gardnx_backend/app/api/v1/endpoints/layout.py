"""Garden layout generation and validation endpoints."""

import logging
import math

from fastapi import APIRouter, Depends

from app.api.deps import get_current_user
from app.models.layout_models import (
    LayoutRequest,
    LayoutResponse,
    ValidationRequest,
    ValidationResponse,
    SpacingRequest,
    SpacingResponse,
    RecommendBedRequest,
    RecommendBedResponse,
    BedSuggestion,
)
from app.models.plant_models import RecommendRequest
from app.config import settings
from app.services.layout_generator import LayoutGenerator
from app.services.companion_checker import CompanionChecker
from app.services.gemini_companion_checker import GeminiCompanionChecker
from app.services.gemini_recommender import GeminiRecommender
from app.services.ollama_recommender import OllamaRecommender
from app.services.plant_recommender import PlantRecommender
from app.services.spacing_calculator import calculate_max_plants

logger = logging.getLogger("gardnx")
router = APIRouter()

# Singleton instances
_layout_gen: LayoutGenerator | None = None
_companion: CompanionChecker | None = None
_gemini_companion: GeminiCompanionChecker | None = None
_plant_rec: PlantRecommender | None = None
_gemini_rec: GeminiRecommender | None = None
_ollama_rec: OllamaRecommender | None = None


def _get_layout_generator() -> LayoutGenerator:
    global _layout_gen
    if _layout_gen is None:
        _layout_gen = LayoutGenerator()
    return _layout_gen


def _get_companion_checker() -> CompanionChecker:
    global _companion
    if _companion is None:
        _companion = CompanionChecker()
    return _companion


def _get_gemini_companion_checker() -> GeminiCompanionChecker:
    global _gemini_companion
    if _gemini_companion is None:
        _gemini_companion = GeminiCompanionChecker(api_key=settings.gemini_api_key)
    return _gemini_companion


def _get_plant_recommender() -> PlantRecommender:
    global _plant_rec
    if _plant_rec is None:
        _plant_rec = PlantRecommender()
    return _plant_rec


def _get_gemini_recommender() -> GeminiRecommender:
    global _gemini_rec
    if _gemini_rec is None:
        _gemini_rec = GeminiRecommender(api_key=settings.gemini_api_key)
    return _gemini_rec


def _get_ollama_recommender() -> OllamaRecommender:
    global _ollama_rec
    if _ollama_rec is None:
        _ollama_rec = OllamaRecommender()
    return _ollama_rec


@router.post("/generate", response_model=LayoutResponse)
async def generate_layout(
    body: LayoutRequest,
    user_id: str = Depends(get_current_user),
):
    """Generate an optimised garden bed layout.

    Accepts bed dimensions and a list of selected plants with quantities.
    Returns a grid-based layout with placements, utilisation statistics,
    and companion-planting warnings.
    """
    generator = _get_layout_generator()
    result = generator.generate(body)

    logger.info(
        "Layout generated: %d placements, %.1f%% utilisation, %d warnings",
        len(result.placements),
        result.statistics.utilization_percent,
        len(result.warnings),
    )
    return result


@router.post("/validate", response_model=ValidationResponse)
async def validate_layout(
    body: ValidationRequest,
    user_id: str = Depends(get_current_user),
):
    """Validate an existing layout for companion-planting conflicts.

    Checks every placed plant against its neighbours (including diagonals)
    and returns any warnings or errors.
    """
    # Try AI companion check first; fall back to static rules if offline/unavailable
    gemini = _get_gemini_companion_checker()
    warnings = gemini.check_layout(
        placements=body.placements,
        bed_width_cm=body.bed.width_cm,
        bed_height_cm=body.bed.height_cm,
    )
    if warnings is None:
        logger.info("Validate: Gemini unavailable, using static companion rules")
        checker = _get_companion_checker()
        warnings = checker.check_layout(
            placements=body.placements,
            bed_width_cm=body.bed.width_cm,
            bed_height_cm=body.bed.height_cm,
        )

    errors = [w for w in warnings if w.severity == "error"]

    logger.info("Validation: %d warnings, %d errors", len(warnings), len(errors))

    return ValidationResponse(
        is_valid=len(errors) == 0,
        warnings=warnings,
        total_warnings=len(warnings),
        total_errors=len(errors),
    )


@router.post("/spacing", response_model=SpacingResponse)
async def calculate_spacing(
    body: SpacingRequest,
    user_id: str = Depends(get_current_user),
):
    """Calculate the maximum number of plants that fit in a bed.

    Given bed dimensions and plant spacing requirements, returns
    the grid layout (rows x cols) and actual spacing values.
    """
    result = calculate_max_plants(
        bed_width_cm=body.bed_width_cm,
        bed_height_cm=body.bed_height_cm,
        spacing_between_cm=body.between_plants_cm,
        spacing_rows_cm=body.between_rows_cm,
    )

    total_area = body.bed_width_cm * body.bed_height_cm
    used_area = result["max_count"] * body.between_plants_cm * body.between_rows_cm
    utilisation = min(100.0, (used_area / total_area) * 100) if total_area > 0 else 0

    return SpacingResponse(
        max_plants=result["max_count"],
        rows=result["rows"],
        cols=result["cols"],
        actual_between_plants_cm=result["cell_width_cm"],
        actual_between_rows_cm=result["cell_height_cm"],
        bed_utilization_percent=round(utilisation, 1),
    )


# Season name → list of sowing months
_SEASON_MONTHS: dict[str, list[int]] = {
    "summer": [11, 12, 1, 2, 3],
    "winter": [5, 6, 7, 8, 9],
    "autumn": [3, 4, 5],
    "spring": [9, 10, 11],
}


@router.post("/recommend", response_model=RecommendBedResponse)
async def recommend_plants_for_bed(
    body: RecommendBedRequest,
    user_id: str = Depends(get_current_user),
):
    """Recommend suitable plants for a garden bed.

    Engine priority: Gemini 2.5 Flash Lite → Ollama (local) → rule-based.
    Falls back transparently — the client always gets results.
    """
    rec = _get_plant_recommender()
    season_months = _SEASON_MONTHS.get(body.season.lower(), list(range(1, 13)))
    current_month = season_months[0] if season_months else 1

    # Shared contract: reuse the same engine chain and request model as
    # /plants/recommend so preferences + experience_level actually affect
    # recommendations and the UI can show engine_used / fallback_reason.
    ai_req = RecommendRequest(
        bed_sunlight=body.sun_exposure,
        bed_soil_type=body.soil_type,
        month=current_month,
        region=body.region,
        preferences=body.preferences,
        experience_level=body.experience_level,  # type: ignore[arg-type]
        preferred_engine=body.preferred_engine,
    )

    from app.api.v1.endpoints.plants import _run_engine_chain
    ai_result, engine_used, engine_requested, fallback_reason = await _run_engine_chain(
        ai_req, rec, _get_gemini_recommender(), _get_ollama_recommender(),
    )

    def _max_count_for_plant(plant) -> int:
        """How many of this plant fit in the bed using the same grid math as the layout generator."""
        cols = max(1, math.floor(body.width_cm / max(plant.spacing.between_plants_cm, 15.0)))
        rows = max(1, math.floor(body.height_cm / max(plant.spacing.between_rows_cm, 15.0)))
        return max(1, min(20, rows * cols))

    if engine_used != "rules":
        # Convert AI PlantRecommendation → BedSuggestion
        suggestions: list[BedSuggestion] = []
        for ai_rec in ai_result.recommendations:
            plant = ai_rec.plant
            companion_names = [
                rec.plants[cid].name
                for cid in plant.companion_plants[:3]
                if cid in rec.plants
            ]
            suggestions.append(BedSuggestion(
                plant_id=plant.id,
                plant_name=plant.name,
                suitability_score=round(ai_rec.score, 2),
                reasons=ai_rec.reasons,
                companion_names=companion_names,
                max_count=_max_count_for_plant(plant),
            ))
    else:
        # Pure rule-based fallback
        suggestions = []
        for plant in rec.plants.values():
            score = 0.75
            reasons: list[str] = []

            if plant.conditions.sunlight == body.sun_exposure:
                score = min(score + 0.10, 1.0)
                reasons.append(f"Suits {body.sun_exposure.replace('_', ' ')}")
            if any(m in plant.timing.sowing_months for m in season_months):
                score = min(score + 0.10, 1.0)
                reasons.append("Good planting season")
            if body.region in plant.mauritius_regions:
                score = min(score + 0.05, 1.0)
                reasons.append(f"Grows well in {body.region}")

            if score < 0.35:
                continue

            companion_names = [
                rec.plants[cid].name
                for cid in plant.companion_plants[:3]
                if cid in rec.plants
            ]
            suggestions.append(BedSuggestion(
                plant_id=plant.id,
                plant_name=plant.name,
                suitability_score=round(score, 2),
                reasons=reasons if reasons else ["Suitable for Mauritius climate"],
                companion_names=companion_names,
                max_count=_max_count_for_plant(plant),
            ))

    suggestions.sort(key=lambda s: s.suitability_score, reverse=True)
    logger.info(
        "Bed recommendations [%s → %s]: %d results (sun=%s season=%s region=%s exp=%s)",
        engine_requested or "auto", engine_used, len(suggestions[:15]),
        body.sun_exposure, body.season, body.region, body.experience_level,
    )
    return RecommendBedResponse(
        recommendations=suggestions[:15],
        engine_used=engine_used,
        engine_requested=engine_requested,
        fallback_reason=fallback_reason,
    )
