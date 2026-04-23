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


# Keyword rules for classification. Ordered: the first matching bucket wins.
_CATEGORY_KEYWORDS: list[tuple[str, tuple[str, ...]]] = [
    ("herb", (
        "basil", "mint", "thyme", "parsley", "rosemary", "sage", "oregano",
        "cilantro", "coriander", "chive", "dill", "lavender", "lemon balm",
        "tarragon", "bay", "marjoram",
    )),
    ("fruit", (
        "apple", "pear", "peach", "plum", "cherry", "strawberry", "raspberry",
        "blueberry", "blackberry", "mango", "papaya", "banana", "pineapple",
        "grape", "citrus", "orange", "lemon", "lime", "melon", "watermelon",
        "passionfruit", "fig", "guava", "lychee",
    )),
    ("vegetable", (
        "tomato", "lettuce", "cabbage", "carrot", "onion", "potato", "pepper",
        "chili", "chilli", "bean", "pea", "squash", "cucumber", "zucchini",
        "broccoli", "cauliflower", "spinach", "kale", "chard", "corn", "maize",
        "radish", "beet", "eggplant", "aubergine", "pumpkin", "okra", "garlic",
        "leek", "celery", "turnip", "sweet potato", "yam", "cassava",
    )),
    ("flower", (
        "rose", "tulip", "daisy", "sunflower", "lily", "orchid", "marigold",
        "hibiscus", "jasmine", "peony", "daffodil", "dahlia", "iris", "poppy",
        "petunia", "zinnia", "begonia", "geranium", "pansy", "anthurium",
    )),
    ("tree", ("tree", "oak", "maple", "pine", "palm", "eucalyptus")),
    ("shrub", ("shrub", "hedge", "bush")),
]


def _categorize_perenual(item: dict) -> str:
    """Classify a Perenual species-list item into our internal category.

    Priority: common-name keyword → Perenual cycle/type → fallback 'vegetable'.
    """
    name = (item.get("common_name") or "").lower()
    sci_names = item.get("scientific_name") or []
    sci = sci_names[0].lower() if sci_names else ""
    haystack = f"{name} {sci}"

    for category, keywords in _CATEGORY_KEYWORDS:
        if any(kw in haystack for kw in keywords):
            return category

    # Perenual's own hints — 'cycle' ('Annual'/'Perennial'/'Biennial') and
    # 'type' (sometimes 'flower', 'tree', etc.). Only useful as a weak signal.
    p_type = (item.get("type") or "").lower()
    if p_type in {"herb", "fruit", "vegetable", "flower", "tree", "shrub"}:
        return p_type

    logger.debug(
        "Perenual categorize: no rule matched for '%s' (%s); defaulting to vegetable",
        name, sci,
    )
    return "vegetable"


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

                results.append({
                    "id": f"perenual_{item['id']}",
                    "name": item.get("common_name") or "Unknown Plant",
                    "scientific_name": sci_names[0] if sci_names else "",
                    "category": _categorize_perenual(item),
                    "description": (
                        f"Watering: {item.get('watering', 'Average')}. "
                        f"Cycle: {item.get('cycle', 'Annual')}."
                    ),
                    "image_url": image_url,
                    "conditions": {
                        "min_temp_c": 18.0, "max_temp_c": 35.0,
                        "sun_requirement": sun, "water_needs": water,
                        "suitable_soils": ["loamy"],
                        "min_humidity": 50.0, "max_humidity": 90.0,
                    },
                    "spacing": {
                        "plant_spacing_cm": 30.0, "row_spacing_cm": 30.0,
                        "grid_cells_required": 1,
                    },
                    "timing": {
                        "sow_months": list(range(1, 13)),
                        "transplant_months": [],
                        "harvest_months": list(range(1, 13)),
                        "days_to_maturity": 60, "days_to_transplant": 14,
                    },
                    "companion_plant_ids": [], "incompatible_plant_ids": [],
                    "suitability_score": 0.5, "tags": ["perenual"],
                    "is_native": False, "difficulty_level": "easy",
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
