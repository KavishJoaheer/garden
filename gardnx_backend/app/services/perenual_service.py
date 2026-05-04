"""Perenual Plant API client with in-memory caching.

Perenual (https://perenual.com/docs/api) provides a plant species database
with images, care guides, and growing conditions.

Free tier: 100 requests/day — results are cached for 24 hours per plant to
stay well within that limit.
"""

import logging
import time
from typing import Optional

import httpx

logger = logging.getLogger("gardnx")

BASE_URL = "https://perenual.com/api"
CACHE_TTL = 86400  # 24 hours
LEGACY_IMAGE_HOSTS = (
    "upload.wikimedia.org",
    "commons.wikimedia.org",
    "wikipedia.org",
)

# Map Perenual sunlight values → our internal values
SUNLIGHT_MAP: dict[str, str] = {
    "full_sun": "full_sun",
    "part_shade": "partial_shade",
    "part_sun": "partial_shade",
    "part_sun/part_shade": "partial_shade",
    "filtered_shade": "full_shade",
    "deep_shade": "full_shade",
}

# Map Perenual watering values → our internal values
WATERING_MAP: dict[str, str] = {
    "frequent": "high",
    "average": "moderate",
    "minimum": "low",
    "none": "low",
}

# ---------------------------------------------------------------------------
# Category classification — keyword rules (ordered: first match wins)
# ---------------------------------------------------------------------------
# Each bucket contains a set of substrings; if any appears in the plant's
# common-name or scientific-name, we assign that category.
_CATEGORY_KEYWORDS: list[tuple[str, tuple[str, ...]]] = [
    ("herb", (
        "basil", "mint", "thyme", "parsley", "rosemary", "sage", "oregano",
        "cilantro", "coriander", "chive", "dill", "lavender", "lemon balm",
        "tarragon", "bay", "marjoram", "fennel", "anise", "chamomile",
        "stevia", "lemongrass", "curry leaf",
    )),
    ("fruit", (
        "apple", "pear", "peach", "plum", "cherry", "strawberry", "raspberry",
        "blueberry", "blackberry", "mango", "papaya", "banana", "pineapple",
        "grape", "citrus", "orange", "lemon", "lime", "melon", "watermelon",
        "passionfruit", "fig", "guava", "lychee", "avocado", "coconut",
        "jackfruit", "breadfruit", "starfruit", "carambola", "longan",
        "rambutan", "durian", "sapodilla", "soursop",
    )),
    ("vegetable", (
        "tomato", "lettuce", "cabbage", "carrot", "onion", "potato", "pepper",
        "chili", "chilli", "bean", "pea", "squash", "cucumber", "zucchini",
        "broccoli", "cauliflower", "spinach", "kale", "chard", "corn", "maize",
        "radish", "beet", "eggplant", "aubergine", "pumpkin", "okra", "garlic",
        "leek", "celery", "turnip", "sweet potato", "yam", "cassava",
        "artichoke", "asparagus", "brussels sprout", "collard", "mustard green",
        "watercress", "fennel bulb", "pak choi", "bok choy", "taro",
    )),
    ("flower", (
        "rose", "tulip", "daisy", "sunflower", "lily", "orchid", "marigold",
        "hibiscus", "jasmine", "peony", "daffodil", "dahlia", "iris", "poppy",
        "petunia", "zinnia", "begonia", "geranium", "pansy", "anthurium",
        "bougainvillea", "frangipani", "plumeria", "lantana", "heliconia",
        "bird of paradise", "strelitzia", "chrysanthemum", "carnation",
        "gerbera", "impatiens", "salvia", "verbena", "cosmos", "aster",
    )),
    ("ornamental", (
        "fern", "succulent", "cactus", "aloe", "agave", "palm", "bamboo",
        "grass", "sedge", "rush", "hosta", "philodendron", "pothos", "monstera",
        "dracaena", "sansevieria", "snake plant", "peace lily", "bromeliad",
        "air plant", "tillandsia", "calathea", "maranta", "dieffenbachia",
        "rubber plant", "fiddle leaf", "schefflera", "yucca",
    )),
    ("tree", (
        "tree", "oak", "maple", "pine", "eucalyptus", "teak", "mahogany",
        "neem", "moringa", "casuarina", "acacia", "tamarind",
    )),
    ("shrub", ("shrub", "hedge", "bush", "bougainvillea shrub")),
]


def _categorize_perenual(item: dict) -> str:
    """Classify a Perenual species-list item into our internal category.

    Priority:
    1. Common-name + scientific-name keyword matching (most reliable)
    2. Perenual's ``type`` field (often null, but useful when present)
    3. Perenual's ``cycle`` field as a weak hint
    4. Default to ``'ornamental'`` (much safer than ``'vegetable'``)
    """
    name = (item.get("common_name") or "").lower()
    sci_names = item.get("scientific_name") or []
    sci = sci_names[0].lower() if sci_names else ""
    haystack = f"{name} {sci}"

    for category, keywords in _CATEGORY_KEYWORDS:
        if any(kw in haystack for kw in keywords):
            return category

    # Perenual's own ``type`` field (sometimes "herb", "flower", etc.)
    p_type = (item.get("type") or "").lower()
    if p_type in {"herb", "fruit", "vegetable", "flower", "ornamental", "tree", "shrub"}:
        return p_type

    # If the cycle is "Perennial" it is probably an ornamental or shrub
    cycle = (item.get("cycle") or "").lower()
    if "perennial" in cycle:
        return "ornamental"

    logger.debug(
        "Perenual categorize: no rule matched for '%s' (%s); defaulting to ornamental",
        name, sci,
    )
    # Default to 'ornamental' — far less misleading than 'vegetable'
    return "ornamental"


# ---------------------------------------------------------------------------
# Category-aware defaults for spacing and timing
# ---------------------------------------------------------------------------
# These are sensible fallbacks when Perenual doesn't provide specific data.
# They vary significantly by category so each plant at least looks realistic.

_CATEGORY_SPACING: dict[str, dict] = {
    "vegetable": {"plant_spacing_cm": 30.0, "row_spacing_cm": 45.0, "grid_cells_required": 1},
    "herb":      {"plant_spacing_cm": 20.0, "row_spacing_cm": 25.0, "grid_cells_required": 1},
    "fruit":     {"plant_spacing_cm": 150.0, "row_spacing_cm": 200.0, "grid_cells_required": 4},
    "flower":    {"plant_spacing_cm": 25.0, "row_spacing_cm": 30.0, "grid_cells_required": 1},
    "ornamental":{"plant_spacing_cm": 45.0, "row_spacing_cm": 45.0, "grid_cells_required": 2},
    "tree":      {"plant_spacing_cm": 300.0, "row_spacing_cm": 300.0, "grid_cells_required": 9},
    "shrub":     {"plant_spacing_cm": 90.0, "row_spacing_cm": 90.0, "grid_cells_required": 4},
}

# Typical sowing / harvest months for each category in a tropical/subtropical
# climate like Mauritius (where most months are viable but some are optimal).
_CATEGORY_TIMING: dict[str, dict] = {
    "vegetable": {
        "sow_months": [3, 4, 5, 6, 7, 8, 9],      # cooler dry months
        "transplant_months": [4, 5, 6, 7, 8],
        "harvest_months": [6, 7, 8, 9, 10, 11],
        "days_to_maturity": 75,
        "days_to_transplant": 21,
    },
    "herb": {
        "sow_months": [3, 4, 5, 9, 10, 11],
        "transplant_months": [4, 5, 10, 11],
        "harvest_months": list(range(1, 13)),       # harvest year-round
        "days_to_maturity": 45,
        "days_to_transplant": 14,
    },
    "fruit": {
        "sow_months": [10, 11, 12],
        "transplant_months": [11, 12, 1],
        "harvest_months": [1, 2, 3, 4, 12],
        "days_to_maturity": 365,
        "days_to_transplant": 90,
    },
    "flower": {
        "sow_months": [3, 4, 5, 9, 10],
        "transplant_months": [4, 5, 10],
        "harvest_months": [6, 7, 11, 12],
        "days_to_maturity": 90,
        "days_to_transplant": 28,
    },
    "ornamental": {
        "sow_months": list(range(1, 13)),
        "transplant_months": [3, 4, 9, 10],
        "harvest_months": [],
        "days_to_maturity": 120,
        "days_to_transplant": 30,
    },
    "tree": {
        "sow_months": [10, 11, 12],
        "transplant_months": [11, 12],
        "harvest_months": [],
        "days_to_maturity": 730,
        "days_to_transplant": 180,
    },
    "shrub": {
        "sow_months": [3, 4, 9, 10],
        "transplant_months": [4, 10],
        "harvest_months": [],
        "days_to_maturity": 365,
        "days_to_transplant": 60,
    },
}

_CATEGORY_DIFFICULTY: dict[str, str] = {
    "vegetable": "easy",
    "herb": "easy",
    "fruit": "moderate",
    "flower": "easy",
    "ornamental": "moderate",
    "tree": "hard",
    "shrub": "moderate",
}

_DEFAULT_SPACING = {"plant_spacing_cm": 30.0, "row_spacing_cm": 30.0, "grid_cells_required": 1}
_DEFAULT_TIMING = {
    "sow_months": list(range(1, 13)),
    "transplant_months": [],
    "harvest_months": list(range(1, 13)),
    "days_to_maturity": 60,
    "days_to_transplant": 14,
}


class PerenualService:
    """Client for the Perenual Plant API.

    Responsibilities:
    - Search for a plant by name and return its image URL + Perenual species ID
    - Cache all results for 24 hours to minimise API calls
    - Gracefully return None when the API key is missing or the call fails
    """

    def __init__(self, api_key: str):
        self._api_key = api_key
        # cache: scientific_name_lower -> (timestamp, result_dict | {})
        self._cache: dict[str, tuple[float, dict]] = {}

    # ------------------------------------------------------------------
    # Cache helpers
    # ------------------------------------------------------------------

    def _get_cache(self, key: str) -> Optional[dict]:
        entry = self._cache.get(key)
        if entry is None:
            return None
        ts, data = entry
        if time.time() - ts > CACHE_TTL:
            del self._cache[key]
            return None
        return data

    def _set_cache(self, key: str, data: dict) -> None:
        self._cache[key] = (time.time(), data)

    def uses_legacy_image_source(self, image_url: Optional[str]) -> bool:
        """Return True for old Wikipedia/Wikimedia image URLs."""
        if not image_url:
            return False
        image_url_lower = image_url.lower()
        return any(host in image_url_lower for host in LEGACY_IMAGE_HOSTS)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def search_plant(
        self,
        name: str,
        scientific_name: str = "",
    ) -> Optional[dict]:
        """Search Perenual for a plant and return enrichment data.

        Returns a dict with keys:
            perenual_id  (int)
            image_url    (str | None)
        or None if not found / API unavailable.
        """
        cache_key = (scientific_name or name).lower()
        cached = self._get_cache(cache_key)
        if cached is not None:
            return cached or None  # empty dict means "not found, skip"

        if not self._api_key:
            return None

        query = scientific_name or name
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(
                    f"{BASE_URL}/species-list",
                    params={"key": self._api_key, "q": query},
                )
                resp.raise_for_status()
                results = resp.json().get("data", [])

            if not results:
                self._set_cache(cache_key, {})
                return None

            first = results[0]
            image_url: Optional[str] = None
            img = first.get("default_image")
            if img:
                image_url = (
                    img.get("regular_url")
                    or img.get("medium_url")
                    or img.get("small_url")
                )

            result = {
                "perenual_id": first.get("id"),
                "image_url": image_url,
            }
            self._set_cache(cache_key, result)
            logger.debug("Perenual hit for '%s': id=%s", query, result["perenual_id"])
            return result

        except httpx.HTTPStatusError as e:
            if e.response.status_code == 429:
                logger.warning("Perenual rate limit hit (429). Will retry after cache TTL.")
            else:
                logger.warning("Perenual HTTP error for '%s': %s", query, e)
            self._set_cache(cache_key, {})
            return None
        except Exception as e:
            logger.warning("Perenual search failed for '%s': %s", query, e)
            self._set_cache(cache_key, {})
            return None

    async def search_catalog(self, query: str, page: int = 1) -> list[dict]:
        """Search Perenual for plants matching *query*.

        Returns a list of Flutter-compatible plant dicts (max 20 per page).
        Results are cached 24 h to protect the daily quota.

        Improvements over v1:
        - Accurate category detection using expanded keyword rules
        - Category-aware spacing defaults (herb ≠ tree ≠ vegetable)
        - Category-aware timing defaults (seasonal planting windows)
        - Default type 'ornamental' instead of 'vegetable' when unknown
        """
        cache_key = f"catalog:{query.lower()}:p{page}"
        cached = self._get_cache(cache_key)
        if cached is not None:
            return cached.get("results", [])

        if not self._api_key:
            return []

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(
                    f"{BASE_URL}/species-list",
                    params={"key": self._api_key, "q": query, "page": page},
                )
                resp.raise_for_status()
                items = resp.json().get("data", [])

            results: list[dict] = []
            for item in items[:20]:
                image_url: Optional[str] = None
                img = item.get("default_image")
                if img:
                    image_url = (
                        img.get("regular_url")
                        or img.get("medium_url")
                        or img.get("small_url")
                    )

                sunlight_raw = item.get("sunlight") or []
                sun = SUNLIGHT_MAP.get(
                    sunlight_raw[0].lower().replace(" ", "_") if sunlight_raw else "",
                    "full_sun",
                )
                watering = (item.get("watering") or "Average").lower()
                water = WATERING_MAP.get(watering, "moderate")
                sci_names = item.get("scientific_name") or []

                # Use improved categorisation so plants aren't all "vegetable"
                category = _categorize_perenual(item)

                # Category-aware spacing & timing — each plant type has
                # realistic defaults instead of every plant showing 30cm spacing
                spacing = _CATEGORY_SPACING.get(category, _DEFAULT_SPACING)
                timing = _CATEGORY_TIMING.get(category, _DEFAULT_TIMING)
                difficulty = _CATEGORY_DIFFICULTY.get(category, "easy")

                cycle = item.get("cycle") or "Annual"
                description = (
                    f"{item.get('common_name', 'Unknown')} — "
                    f"Watering: {item.get('watering', 'Average')}. "
                    f"Cycle: {cycle}. "
                    f"Category: {category.capitalize()}."
                )

                results.append({
                    "id": f"perenual_{item['id']}",
                    "name": item.get("common_name") or "Unknown Plant",
                    "scientific_name": sci_names[0] if sci_names else "",
                    "category": category,
                    "description": description,
                    "image_url": image_url,
                    "conditions": {
                        "min_temp_c": 18.0, "max_temp_c": 35.0,
                        "sun_requirement": sun, "water_needs": water,
                        "suitable_soils": ["loamy"],
                        "min_humidity": 50.0, "max_humidity": 90.0,
                    },
                    "spacing": spacing,
                    "timing": timing,
                    "companion_plant_ids": [], "incompatible_plant_ids": [],
                    "suitability_score": 0.5,
                    "tags": ["perenual", category],
                    "is_native": False,
                    "difficulty_level": difficulty,
                })

            self._set_cache(cache_key, {"results": results})
            logger.debug("Perenual catalog '%s' p%d → %d results", query, page, len(results))
            return results

        except httpx.HTTPStatusError as e:
            if e.response.status_code == 429:
                logger.warning("Perenual rate limit (429) on catalog search.")
            else:
                logger.warning("Perenual catalog search HTTP error: %s", e)
            self._set_cache(cache_key, {"results": []})
            return []
        except Exception as e:
            logger.warning("Perenual catalog search failed for '%s': %s", query, e)
            return []

    async def enrich_plants(self, plants: list, max_lookups: int = 10) -> list:
        """Return a new list of plants enriched with Perenual image URLs.

        Only the first *max_lookups* plants without an image or with a legacy
        Wikipedia/Wikimedia image are looked up to respect the daily rate
        limit. Plants that already have a non-legacy image_url are left
        unchanged.
        """
        enriched = []
        lookups_done = 0

        for plant in plants:
            should_replace_image = (
                plant.image_url is None
                or self.uses_legacy_image_source(plant.image_url)
            )
            if should_replace_image and lookups_done < max_lookups:
                data = await self.search_plant(
                    name=plant.name,
                    scientific_name=plant.scientific_name,
                )
                lookups_done += 1
                if data and data.get("image_url"):
                    plant = plant.model_copy(update={
                        "image_url": data["image_url"],
                        "perenual_id": data.get("perenual_id"),
                    })
            enriched.append(plant)

        return enriched
