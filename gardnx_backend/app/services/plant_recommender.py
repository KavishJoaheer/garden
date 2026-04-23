"""Plant recommendation engine with weighted scoring algorithm."""

import json
import logging
from pathlib import Path
from typing import Dict, List

from app.models.plant_models import (
    Plant,
    PlantRecommendation,
    RecommendRequest,
    RecommendResponse,
)

logger = logging.getLogger("gardnx")

# Scoring weights (must sum to 1.0)
W_SUN = 0.25
W_SEASON = 0.25
W_TEMP = 0.20
W_REGION = 0.15
W_PREF = 0.15

# Adjacent sun levels for partial matching
SUN_ADJACENCY = {
    "full_sun": ["full_sun", "partial_shade"],
    "partial_shade": ["partial_shade", "full_sun", "full_shade"],
    "full_shade": ["full_shade", "partial_shade"],
}

DATA_DIR = Path(__file__).resolve().parent.parent / "data"


class PlantRecommender:
    """Loads the plant catalog from JSON and scores plants for a given request.

    Scoring dimensions (weights):
        - sun_match  (0.25): exact match = 1.0, adjacent = 0.5, mismatch = 0.0
        - season     (0.25): month is in sowing_months = 1.0, adjacent month = 0.5
        - temp       (0.20): how well current temp fits plant's range
        - region     (0.15): region is in plant's mauritius_regions
        - preference (0.15): type or tag matches user preferences
    """

    def __init__(self, plants_json_path: str | None = None):
        path = Path(plants_json_path) if plants_json_path else DATA_DIR / "plants_mauritius.json"
        self.plants: Dict[str, Plant] = {}
        self._load_plants(path)

    def _load_plants(self, path: Path) -> None:
        """Load the plant catalog from a JSON file."""
        try:
            with open(path, "r", encoding="utf-8") as f:
                raw = json.load(f)
            for item in raw:
                plant = Plant(**item)
                self.plants[plant.id] = plant
            logger.info("PlantRecommender: loaded %d plants from %s", len(self.plants), path)
        except FileNotFoundError:
            logger.warning("PlantRecommender: plant file not found at %s", path)
        except Exception as e:
            logger.error("PlantRecommender: error loading plants: %s", e)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def recommend(self, req: RecommendRequest) -> RecommendResponse:
        """Score and rank plants for the given request."""
        scored: List[PlantRecommendation] = []

        for plant in self.plants.values():
            # Skip excluded plants
            if plant.id in req.exclude_plant_ids:
                continue

            # Hard filters -- skip plants that absolutely cannot grow
            if not self._passes_hard_filter(plant, req):
                continue

            sun_sc, sun_reason = self._score_sun(plant, req.bed_sunlight)
            season_sc, season_reason = self._score_season(plant, req.month)
            temp_sc, temp_reason = self._score_temp(plant, req.current_temp_c)
            region_sc, region_reason = self._score_region(plant, req.region)
            pref_sc, pref_reason = self._score_preference(plant, req.preferences)

            total = (
                W_SUN * sun_sc
                + W_SEASON * season_sc
                + W_TEMP * temp_sc
                + W_REGION * region_sc
                + W_PREF * pref_sc
            )

            reasons = [r for r in [sun_reason, season_reason, temp_reason, region_reason, pref_reason] if r]

            scored.append(
                PlantRecommendation(
                    plant=plant,
                    score=round(total, 3),
                    reasons=reasons,
                    sun_score=round(sun_sc, 3),
                    season_score=round(season_sc, 3),
                    temp_score=round(temp_sc, 3),
                    region_score=round(region_sc, 3),
                    preference_score=round(pref_sc, 3),
                )
            )

        # Sort by total score descending, take top 20
        scored.sort(key=lambda r: r.score, reverse=True)
        top = scored[:20]

        return RecommendResponse(
            recommendations=top,
            total=len(top),
            filters_applied={
                "bed_sunlight": req.bed_sunlight,
                "month": req.month,
                "region": req.region,
                "preferences": req.preferences,
            },
        )

    # ------------------------------------------------------------------
    # Hard filters
    # ------------------------------------------------------------------

    def _passes_hard_filter(self, plant: Plant, req: RecommendRequest) -> bool:
        """Return False if the plant should be excluded entirely."""
        # Wrong sun category with no adjacency at all
        sun_adj = SUN_ADJACENCY.get(req.bed_sunlight, [req.bed_sunlight])
        if plant.conditions.sunlight not in sun_adj:
            return False
        # Experience-level gate: beginners avoid water-intensive or long-cycle
        # crops. Plant model has no explicit difficulty, so use proxies:
        #   - water_needs == "high"     → non-beginner
        #   - days_to_harvest > 120     → non-beginner
        if req.experience_level == "beginner":
            if plant.conditions.water_needs == "high":
                return False
            if plant.timing.days_to_harvest > 120:
                return False
        return True

    # ------------------------------------------------------------------
    # Scoring helpers
    # ------------------------------------------------------------------

    def _score_sun(self, plant: Plant, bed_sun: str) -> tuple[float, str]:
        """Score sun compatibility."""
        if plant.conditions.sunlight == bed_sun:
            return 1.0, f"Ideal sun match ({bed_sun})"
        adj = SUN_ADJACENCY.get(bed_sun, [])
        if plant.conditions.sunlight in adj:
            return 0.5, f"Tolerates {bed_sun} (prefers {plant.conditions.sunlight})"
        return 0.0, ""

    def _score_season(self, plant: Plant, month: int) -> tuple[float, str]:
        """Score sowing-season suitability."""
        if month in plant.timing.sowing_months:
            return 1.0, f"Ideal sowing month (month {month})"
        # Check adjacent months
        adj = [(month - 1) if month > 1 else 12, (month + 1) if month < 12 else 1]
        if any(m in plant.timing.sowing_months for m in adj):
            return 0.5, f"Near sowing season (adjacent month)"
        # Check if it is harvest time (still relevant)
        if month in plant.timing.harvest_months:
            return 0.3, "Currently in harvest season (sow earlier)"
        return 0.0, ""

    def _score_temp(self, plant: Plant, current_temp: float | None) -> tuple[float, str]:
        """Score temperature compatibility."""
        if current_temp is None:
            # Use a sensible Mauritius default
            current_temp = 26.0

        min_t = plant.conditions.min_temp_c
        max_t = plant.conditions.max_temp_c

        if min_t <= current_temp <= max_t:
            # How centred within the range?
            mid = (min_t + max_t) / 2
            spread = (max_t - min_t) / 2 if max_t != min_t else 1
            closeness = 1.0 - abs(current_temp - mid) / spread
            score = 0.7 + 0.3 * max(0, closeness)
            return round(score, 3), f"Temperature {current_temp}C within range ({min_t}-{max_t}C)"

        # Outside range but close
        if current_temp < min_t:
            diff = min_t - current_temp
        else:
            diff = current_temp - max_t

        if diff <= 3:
            return 0.4, f"Temperature {current_temp}C slightly outside range ({min_t}-{max_t}C)"
        if diff <= 6:
            return 0.2, f"Temperature {current_temp}C moderately outside range ({min_t}-{max_t}C)"
        return 0.0, ""

    def _score_region(self, plant: Plant, region: str) -> tuple[float, str]:
        """Score region compatibility."""
        if region in plant.mauritius_regions:
            return 1.0, f"Grows well in {region} Mauritius"
        return 0.0, ""

    def _score_preference(self, plant: Plant, preferences: List[str]) -> tuple[float, str]:
        """Score match with user preferences."""
        if not preferences:
            return 0.5, ""  # Neutral when no preferences given

        matches = 0
        reasons_parts: List[str] = []

        for pref in preferences:
            pref_lower = pref.lower()
            # Check type match
            if pref_lower in ("vegetables", "vegetable") and plant.type == "vegetable":
                matches += 1
                reasons_parts.append("vegetable")
            elif pref_lower in ("herbs", "herb") and plant.type == "herb":
                matches += 1
                reasons_parts.append("herb")
            elif pref_lower in ("fruits", "fruit") and plant.type == "fruit":
                matches += 1
                reasons_parts.append("fruit")
            elif pref_lower in ("flowers", "flower") and plant.type == "flower":
                matches += 1
                reasons_parts.append("flower")
            # Check care attributes
            elif pref_lower == "low_maintenance" and plant.conditions.water_needs == "low":
                matches += 1
                reasons_parts.append("low maintenance")
            elif pref_lower == "fast_growing" and plant.timing.days_to_harvest <= 60:
                matches += 1
                reasons_parts.append("fast growing")
            elif pref_lower == "drought_tolerant" and plant.conditions.water_needs == "low":
                matches += 1
                reasons_parts.append("drought tolerant")

        if matches == 0:
            return 0.0, ""

        score = min(1.0, matches / len(preferences))
        reason = f"Matches preferences: {', '.join(reasons_parts)}"
        return round(score, 3), reason
