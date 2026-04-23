"""Ollama local LLM recommender.

Calls a locally-running Ollama instance (http://localhost:11434) to generate
plant recommendations using any downloaded model (e.g. gemma3:1b).

Completely offline — no API key, no quota, no cost.
Falls back to None so the caller can chain to Gemini or rule-based.
"""

import json
import logging
import time
from typing import Optional

import httpx

from app.config import settings
from app.models.plant_models import (
    Plant,
    PlantRecommendation,
    RecommendRequest,
    RecommendResponse,
)

logger = logging.getLogger("gardnx")

CACHE_TTL = 86400  # 24 hours

_SYSTEM_PROMPT = """\
You are an expert agricultural advisor for home gardening in Mauritius.
Given a garden bed description and a plant catalog, recommend the best plants.

IMPORTANT: Reply with ONLY valid JSON — no markdown, no explanation, no code fences.

Output format:
{
  "recommendations": [
    {
      "plant_id": "<id>",
      "score": <float 0.0-1.0>,
      "reasons": ["<short reason>", "<short reason>"],
      "sun_score": <float>,
      "season_score": <float>,
      "temp_score": <float>,
      "region_score": <float>,
      "preference_score": <float>
    }
  ]
}

Return at most 15 items, ordered by score descending.\
"""

_MONTH_NAMES = [
    "", "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]


class OllamaRecommender:
    """Uses a local Ollama model for plant recommendations."""

    def __init__(self, model: str | None = None, base_url: str | None = None):
        self._model = model or settings.ollama_model
        self._base_url = (base_url or settings.ollama_url).rstrip("/")
        self._cache: dict[str, tuple[float, RecommendResponse]] = {}

    @property
    def _generate_url(self) -> str:
        return f"{self._base_url}/api/generate"

    # ------------------------------------------------------------------
    # Cache helpers
    # ------------------------------------------------------------------

    def _cache_key(self, req: RecommendRequest) -> str:
        prefs = ",".join(sorted(req.preferences))
        exp = req.experience_level or ""
        return f"ollama|{req.bed_sunlight}|{req.region}|{req.month}|{prefs}|{exp}"

    def _get_cache(self, key: str) -> Optional[RecommendResponse]:
        entry = self._cache.get(key)
        if entry is None:
            return None
        ts, data = entry
        if time.time() - ts > CACHE_TTL:
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
        """Return AI recommendations or None if Ollama is not running."""
        key = self._cache_key(req)
        cached = self._get_cache(key)
        if cached is not None:
            logger.debug("Ollama cache hit for key=%s", key)
            return cached

        prompt = self._build_prompt(req, plants)

        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                resp = await client.post(
                    self._generate_url,
                    json={
                        "model": self._model,
                        "system": _SYSTEM_PROMPT,
                        "prompt": prompt,
                        "stream": False,
                        "options": {"temperature": 0.2, "num_predict": 2048},
                    },
                )
                resp.raise_for_status()
                text = resp.json().get("response", "")

            result = self._parse_response(text, req, plants)
            if result:
                self._set_cache(key, result)
                logger.info(
                    "Ollama [%s] recommendation OK — %d results cached 24h",
                    self._model, result.total,
                )
            return result

        except httpx.ConnectError:
            logger.debug("Ollama not running — skipping local AI")
            return None
        except Exception as e:
            logger.warning("Ollama recommendation failed: %s", e)
            return None

    # ------------------------------------------------------------------
    # Prompt builder
    # ------------------------------------------------------------------

    def _build_prompt(self, req: RecommendRequest, plants: dict[str, Plant]) -> str:
        month_name = _MONTH_NAMES[req.month]
        temp_str = f"{req.current_temp_c}°C" if req.current_temp_c else "~26°C"
        prefs_str = ", ".join(req.preferences) if req.preferences else "none"

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
                "regions": plant.mauritius_regions,
                "water": plant.conditions.water_needs,
                "days_to_harvest": plant.timing.days_to_harvest,
            })

        audience = req.experience_level or "intermediate"
        return (
            f"Garden bed: sun={req.bed_sunlight}, soil={req.bed_soil_type}, "
            f"region={req.region} Mauritius, month={month_name} ({req.month}), "
            f"temp={temp_str}, preferences={prefs_str}, audience={audience} gardener\n\n"
            f"Plant catalog ({len(catalog)} plants):\n"
            f"{json.dumps(catalog, separators=(',', ':'))}"
        )

    # ------------------------------------------------------------------
    # Response parser
    # ------------------------------------------------------------------

    def _parse_response(
        self,
        text: str,
        req: RecommendRequest,
        plants: dict[str, Plant],
    ) -> Optional[RecommendResponse]:
        try:
            clean = text.strip()
            # Strip markdown fences if present
            if "```" in clean:
                parts = clean.split("```")
                # Take the first code block content
                for part in parts[1::2]:
                    if part.startswith("json"):
                        part = part[4:]
                    clean = part.strip()
                    break

            # Find the outermost JSON object
            start = clean.find("{")
            end = clean.rfind("}") + 1
            if start == -1 or end == 0:
                logger.warning("Ollama: no JSON object found in response")
                return None
            clean = clean[start:end]

            data = json.loads(clean)
            recs_raw = data.get("recommendations", [])

            def _norm(val, default: float = 0.0) -> float:
                """Normalise score to 0–1. Small models often output 0–10."""
                f = float(val) if val is not None else default
                return round(min(f / 10.0, 1.0) if f > 1.0 else f, 3)

            recommendations: list[PlantRecommendation] = []
            for item in recs_raw:
                plant_id = item.get("plant_id", "")
                plant = plants.get(plant_id)
                if plant is None:
                    continue  # model hallucinated an id

                recommendations.append(PlantRecommendation(
                    plant=plant,
                    score=_norm(item.get("score"), 0.5),
                    reasons=item.get("reasons", ["Recommended by local AI"]),
                    sun_score=_norm(item.get("sun_score")),
                    season_score=_norm(item.get("season_score")),
                    temp_score=_norm(item.get("temp_score")),
                    region_score=_norm(item.get("region_score")),
                    preference_score=_norm(item.get("preference_score")),
                ))

            if not recommendations:
                return None

            return RecommendResponse(
                recommendations=recommendations,
                total=len(recommendations),
                filters_applied={
                    "engine": f"ollama/{self._model}",
                    "bed_sunlight": req.bed_sunlight,
                    "month": req.month,
                    "region": req.region,
                    "preferences": req.preferences,
                },
            )

        except (json.JSONDecodeError, KeyError, ValueError) as e:
            logger.warning("Ollama parse error: %s\nRaw (first 300): %.300s", e, text)
            return None
