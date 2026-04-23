"""Gemini-powered plant recommendation service.

Uses Google Gemini 2.5 Flash Lite to reason over the Mauritius plant catalog
and produce scored recommendations with natural-language explanations.

Falls back silently to None so the caller can switch to the rule-based engine.
"""

import json
import logging
import time
from typing import Optional

import google.generativeai as genai

from app.models.plant_models import (
    Plant,
    PlantRecommendation,
    RecommendRequest,
    RecommendResponse,
)

logger = logging.getLogger("gardnx")

# Month number → name
_MONTH_NAMES = [
    "", "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]

_SYSTEM_PROMPT = """\
You are an expert agricultural advisor specialising in home gardening in Mauritius.
You will be given a garden bed description and a catalog of plants suitable for Mauritius.
Your task is to recommend the best plants for the bed and explain why.

Rules:
- Consider sun exposure, current month (sowing season), temperature, region, and user preferences.
- Score each recommended plant from 0.0 to 1.0 (higher = better fit).
- Return ONLY valid JSON — no markdown, no commentary.
- Return at most 15 recommendations, ordered by score descending.
- Each reason must be a short, friendly English sentence (max 12 words).

Output format (strict JSON):
{
  "recommendations": [
    {
      "plant_id": "<id from catalog>",
      "score": <float 0-1>,
      "reasons": ["<reason 1>", "<reason 2>"],
      "sun_score": <float 0-1>,
      "season_score": <float 0-1>,
      "temp_score": <float 0-1>,
      "region_score": <float 0-1>,
      "preference_score": <float 0-1>
    }
  ]
}
"""


class GeminiRecommender:
    """Wraps the Gemini API for plant recommendations.

    Caches responses for 24 hours keyed on (sun, region, month, preferences)
    so repeated requests from the same garden never burn extra quota.
    """

    _CACHE_TTL = 86400  # 24 hours

    def __init__(self, api_key: str):
        self._enabled = bool(api_key)
        # cache: cache_key -> (timestamp, RecommendResponse)
        self._cache: dict[str, tuple[float, RecommendResponse]] = {}
        if self._enabled:
            genai.configure(api_key=api_key)
            self._model = genai.GenerativeModel(
                model_name="gemini-2.5-flash-lite",
                system_instruction=_SYSTEM_PROMPT,
                generation_config=genai.GenerationConfig(
                    temperature=0.3,        # low temp = consistent, factual output
                    max_output_tokens=4096,
                ),
            )

    def _cache_key(self, req: RecommendRequest) -> str:
        prefs = ",".join(sorted(req.preferences))
        exp = req.experience_level or ""
        return f"{req.bed_sunlight}|{req.region}|{req.month}|{prefs}|{exp}"

    def _get_cache(self, key: str) -> Optional[RecommendResponse]:
        entry = self._cache.get(key)
        if entry is None:
            return None
        ts, data = entry
        if time.time() - ts > self._CACHE_TTL:
            del self._cache[key]
            return None
        return data

    def _set_cache(self, key: str, data: RecommendResponse) -> None:
        self._cache[key] = (time.time(), data)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def recommend(
        self,
        req: RecommendRequest,
        plants: dict[str, Plant],
    ) -> Optional[RecommendResponse]:
        """Return AI recommendations or None if Gemini is unavailable.

        Results are cached 24 h per (sun, region, month, preferences) tuple
        so the same garden bed never triggers more than one API call per day.
        """
        if not self._enabled:
            return None

        key = self._cache_key(req)
        cached = self._get_cache(key)
        if cached is not None:
            logger.debug("Gemini cache hit for key=%s", key)
            return cached

        try:
            prompt = self._build_prompt(req, plants)
            response = await self._model.generate_content_async(prompt)
            result = self._parse_response(response.text, req, plants)
            if result:
                self._set_cache(key, result)
                logger.info("Gemini recommendation OK — cached for 24 h (key=%s)", key)
            return result
        except Exception as e:
            logger.warning("Gemini recommendation failed: %s", e)
            return None

    # ------------------------------------------------------------------
    # Prompt builder
    # ------------------------------------------------------------------

    def _build_prompt(self, req: RecommendRequest, plants: dict[str, Plant]) -> str:
        month_name = _MONTH_NAMES[req.month]
        temp_str = f"{req.current_temp_c}°C" if req.current_temp_c else "~26°C (typical Mauritius)"
        prefs_str = ", ".join(req.preferences) if req.preferences else "no specific preferences"

        # Compact plant catalog — only the fields Gemini needs for scoring
        catalog = []
        for plant in plants.values():
            if plant.id in req.exclude_plant_ids:
                continue
            catalog.append({
                "id": plant.id,
                "name": plant.name,
                "type": plant.type,
                "sun": plant.conditions.sunlight,
                "sow_months": plant.timing.sowing_months,
                "harvest_months": plant.timing.harvest_months,
                "days_to_harvest": plant.timing.days_to_harvest,
                "regions": plant.mauritius_regions,
                "water": plant.conditions.water_needs,
                "temp_range": [plant.conditions.min_temp_c, plant.conditions.max_temp_c],
                "companions": plant.companion_plants[:3],   # keep prompt compact
                "incompatible": plant.incompatible_plants[:3],
            })

        audience = req.experience_level or "intermediate"
        return f"""GARDEN BED PARAMETERS:
- Sun exposure: {req.bed_sunlight}
- Soil type: {req.bed_soil_type}
- Region: {req.region} Mauritius
- Month: {month_name} (month {req.month})
- Current temperature: {temp_str}
- User preferences: {prefs_str}
- Audience: {audience} gardener (beginner = favour easy, low-water, fast crops; advanced = all plants welcome)

PLANT CATALOG ({len(catalog)} plants):
{json.dumps(catalog, indent=2)}

Please recommend the best plants for this garden bed."""

    # ------------------------------------------------------------------
    # Response parser
    # ------------------------------------------------------------------

    def _parse_response(
        self,
        text: str,
        req: RecommendRequest,
        plants: dict[str, Plant],
    ) -> Optional[RecommendResponse]:
        """Parse Gemini JSON output into a RecommendResponse."""
        try:
            # Strip any accidental markdown code fences
            clean = text.strip()
            if clean.startswith("```"):
                clean = clean.split("```")[1]
                if clean.startswith("json"):
                    clean = clean[4:]
            clean = clean.strip()

            data = json.loads(clean)
            recs_raw = data.get("recommendations", [])

            # Build a name→plant lookup for fuzzy matching when Gemini
            # returns a slightly different ID than what's in the catalog.
            name_index: dict[str, Plant] = {
                p.name.lower(): p for p in plants.values()
            }

            recommendations: list[PlantRecommendation] = []
            for item in recs_raw:
                plant_id = item.get("plant_id", "")
                plant = plants.get(plant_id)

                if plant is None:
                    # Try substring match on ID (e.g. "tomato" matches "tomato_mauritius")
                    for pid, p in plants.items():
                        if plant_id and (plant_id in pid or pid in plant_id):
                            plant = p
                            break

                if plant is None:
                    # Try name match as last resort
                    plant = name_index.get(plant_id.lower().replace("_", " "))

                if plant is None:
                    logger.debug("Gemini returned unknown plant_id=%r — skipping", plant_id)
                    continue

                recommendations.append(PlantRecommendation(
                    plant=plant,
                    score=float(item.get("score", 0.5)),
                    reasons=item.get("reasons", ["Recommended by AI"]),
                    sun_score=float(item.get("sun_score", 0.0)),
                    season_score=float(item.get("season_score", 0.0)),
                    temp_score=float(item.get("temp_score", 0.0)),
                    region_score=float(item.get("region_score", 0.0)),
                    preference_score=float(item.get("preference_score", 0.0)),
                ))

            if not recommendations:
                return None

            return RecommendResponse(
                recommendations=recommendations,
                total=len(recommendations),
                filters_applied={
                    "engine": "gemini-2.5-flash-lite",
                    "bed_sunlight": req.bed_sunlight,
                    "month": req.month,
                    "region": req.region,
                    "preferences": req.preferences,
                },
            )

        except (json.JSONDecodeError, KeyError, ValueError) as e:
            logger.warning("Gemini response parse error: %s\nRaw: %.300s", e, text)
            return None
