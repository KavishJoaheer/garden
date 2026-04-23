"""Gemini-powered companion planting checker.

Uses Google Gemini to reason about companion planting relationships between
plants. Falls back silently to None so the caller can use the static rule-based
CompanionChecker instead.

Caches results for 24 hours per plant pair to avoid redundant API calls.
"""

import json
import logging
import time
from typing import Optional

import google.generativeai as genai

from app.models.layout_models import LayoutWarning, PlantPlacement

logger = logging.getLogger("gardnx")

_SYSTEM_PROMPT = """\
You are an expert agricultural advisor specialising in companion planting for home gardens in Mauritius.
Given two plant names, determine their companion planting relationship.

Rules:
- Return ONLY valid JSON — no markdown, no commentary.
- relationship must be exactly one of: "companion", "incompatible", or "neutral"
- reason must be a single clear English sentence (max 20 words) explaining why.

Output format (strict JSON):
{
  "relationship": "companion" | "incompatible" | "neutral",
  "reason": "<explanation>"
}
"""

# Cache: (sorted plant pair tuple) -> {"relationship": ..., "reason": ..., "expires": float}
_cache: dict[tuple[str, str], dict] = {}
_CACHE_TTL = 86400  # 24 hours


class GeminiCompanionChecker:
    """AI-powered companion planting checker using Google Gemini.

    Checks pairs of plants for companion/incompatible/neutral relationships.
    Returns None for any pair if the API is unavailable, allowing the caller
    to fall back to the static rule-based CompanionChecker.
    """

    def __init__(self, api_key: str):
        self._enabled = bool(api_key)
        if self._enabled:
            genai.configure(api_key=api_key)
            self._model = genai.GenerativeModel(
                model_name="gemini-2.5-flash-lite",
                system_instruction=_SYSTEM_PROMPT,
                generation_config=genai.GenerationConfig(
                    temperature=0.2,
                    max_output_tokens=256,
                ),
            )
            logger.info("GeminiCompanionChecker: initialised with gemini-2.5-flash-lite")
        else:
            logger.warning("GeminiCompanionChecker: no API key — AI companion checks disabled")

    def check_pair(self, plant1_id: str, plant2_id: str) -> Optional[dict]:
        """Check companion relationship between two plants via Gemini.

        Returns a dict with keys 'relationship' and 'reason', or None if
        the API is unavailable / disabled (caller should fall back to static rules).
        """
        if not self._enabled:
            return None

        pair = tuple(sorted([plant1_id, plant2_id]))

        # Check cache
        cached = _cache.get(pair)
        if cached and cached["expires"] > time.time():
            return cached

        prompt = (
            f"Plant A: {plant1_id.replace('_', ' ').title()}\n"
            f"Plant B: {plant2_id.replace('_', ' ').title()}\n"
            "What is their companion planting relationship?"
        )

        try:
            response = self._model.generate_content(prompt)
            text = response.text.strip()
            # Strip markdown code fences if present
            if text.startswith("```"):
                text = text.split("```")[1]
                if text.startswith("json"):
                    text = text[4:]
            data = json.loads(text)

            rel = data.get("relationship", "neutral")
            if rel not in ("companion", "incompatible", "neutral"):
                rel = "neutral"

            result = {
                "relationship": rel,
                "reason": data.get("reason", ""),
                "expires": time.time() + _CACHE_TTL,
            }
            _cache[pair] = result
            logger.debug("GeminiCompanionChecker: %s × %s → %s", plant1_id, plant2_id, rel)
            return result

        except Exception as e:
            logger.warning("GeminiCompanionChecker: API error for %s/%s: %s", plant1_id, plant2_id, e)
            return None

    def check_layout(
        self,
        placements: list[PlantPlacement],
        bed_width_cm: float = 0,
        bed_height_cm: float = 0,
    ) -> Optional[list[LayoutWarning]]:
        """Check all placed plants for companion-planting issues using Gemini.

        Returns a list of LayoutWarning objects, or None if any API call fails
        (so the caller can fall back to static rules for the whole layout).
        """
        if not self._enabled:
            return None

        warnings: list[LayoutWarning] = []
        checked_pairs: set = set()

        # Build spatial index: cell -> plant_id
        cell_map: dict[tuple[int, int], str] = {}
        for p in placements:
            for dr in range(p.span_rows):
                for dc in range(p.span_cols):
                    cell_map[(p.row + dr, p.col + dc)] = p.plant_id

        for (r, c), pid in cell_map.items():
            for dr in [-1, 0, 1]:
                for dc in [-1, 0, 1]:
                    if dr == 0 and dc == 0:
                        continue
                    nr, nc = r + dr, c + dc
                    nid = cell_map.get((nr, nc))
                    if nid is None or nid == pid:
                        continue

                    pair = tuple(sorted([pid, nid]))
                    if pair in checked_pairs:
                        continue
                    checked_pairs.add(pair)

                    result = self.check_pair(pid, nid)
                    if result is None:
                        # API unavailable — signal caller to fall back entirely
                        return None

                    rel = result["relationship"]
                    reason = result["reason"]

                    if rel == "incompatible":
                        warnings.append(LayoutWarning(
                            type="companion_conflict",
                            message=f"{pid} and {nid} are incompatible. {reason}",
                            plant1_id=pid,
                            plant2_id=nid,
                            severity="error",
                        ))
                    elif rel == "companion":
                        warnings.append(LayoutWarning(
                            type="companion_benefit",
                            message=f"{pid} and {nid} are good companions. {reason}",
                            plant1_id=pid,
                            plant2_id=nid,
                            severity="info",
                        ))

        return warnings
