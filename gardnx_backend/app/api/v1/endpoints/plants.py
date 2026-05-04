"""Plant catalog and recommendation endpoints."""

import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from app.api.deps import get_current_user
from app.config import settings
from app.dependencies import (
    get_gemini_recommender,
    get_ollama_recommender,
    get_perenual_service,
    get_plant_recommender,
)
from app.models.plant_models import (
    Plant,
    RecommendRequest,
    RecommendResponse,
)
from app.services.gemini_recommender import GeminiRecommender
from app.services.ollama_recommender import OllamaRecommender
from app.services.plant_recommender import PlantRecommender

logger = logging.getLogger("gardnx")
router = APIRouter()


async def _run_engine_chain(
    req: RecommendRequest,
    recommender: PlantRecommender,
    gemini: GeminiRecommender,
    ollama: OllamaRecommender,
) -> tuple[RecommendResponse, str, str | None, str | None]:
    """Run the engine chain honoring `req.preferred_engine`.

    Returns (result, engine_used, engine_requested, fallback_reason).
    `fallback_reason` is non-None only when the preferred engine was not the
    one that produced the result — it lists each skipped engine's failure."""
    requested = req.preferred_engine
    if requested == "ollama":
        order = [("ollama", ollama), ("gemini", gemini), ("rules", None)]
    elif requested == "rules":
        order = [("rules", None)]
    else:
        order = [("gemini", gemini), ("ollama", ollama), ("rules", None)]

    failures: list[str] = []
    for name, engine in order:
        if name == "rules":
            result = recommender.recommend(req)
            used = "rules"
            break
        try:
            attempt = await engine.recommend(req, recommender.plants)
        except Exception as exc:  # noqa: BLE001 — we want to surface these
            failures.append(f"{name}: {exc}")
            continue
        if attempt is not None and attempt.recommendations:
            result, used = attempt, name
            break
        failures.append(f"{name}: no result")
    else:
        result = recommender.recommend(req)
        used = "rules"

    fallback_reason = "; ".join(failures) if (failures and used != requested) else None
    return result, used, requested, fallback_reason


@router.get("/search")
async def search_plants_global(
    q: str = Query(..., min_length=2, max_length=100, description="Search term"),
    page: int = Query(1, ge=1, description="Perenual page number"),
    user_id: str = Depends(get_current_user),
):
    """Search the global Perenual plant database.

    Returns Flutter-compatible plant JSON objects tagged with
    ``"perenual"`` in their ``tags`` list so the client can
    distinguish them from curated Mauritius plants.

    Results are cached 24 h on the backend — safe to call on
    every search keystroke after debouncing.
    """
    # Sanitize search input
    q_clean = q.strip()
    perenual = get_perenual_service()
    results = await perenual.search_catalog(query=q_clean, page=page)
    logger.info("Global search '%s' p%d → %d results", q_clean, page, len(results))
    return results


@router.get("/catalog", response_model=list[Plant])
async def get_catalog(
    type: Optional[str] = Query(None, description="Filter by plant type (vegetable, herb, fruit, flower)"),
    sun: Optional[str] = Query(None, description="Filter by sun requirement (full_sun, partial_shade, full_shade)"),
    season: Optional[int] = Query(None, ge=1, le=12, description="Filter by sowing month (1-12)"),
    region: Optional[str] = Query(None, description="Filter by Mauritius region"),
    search: Optional[str] = Query(None, max_length=100, description="Search term for plant name"),
    enrich: bool = Query(False, description="Enrich results with Perenual images (uses API quota)"),
    user_id: str = Depends(get_current_user),
):
    """Return the full plant catalog, optionally filtered and Perenual-enriched.

    Pass ?enrich=true to fetch plant images from the Perenual API.
    Images are cached for 24 hours so repeated calls don't burn quota.
    """
    recommender = get_plant_recommender()
    plants = list(recommender.plants.values())

    if type:
        plants = [p for p in plants if p.type == type]
    if sun:
        plants = [p for p in plants if p.conditions.sunlight == sun]
    if season:
        plants = [p for p in plants if season in p.timing.sowing_months]
    if region:
        plants = [p for p in plants if region in p.mauritius_regions]
    if search:
        term = search.strip().lower()
        plants = [
            p for p in plants
            if term in p.name.lower()
            or term in p.name_fr.lower()
            or term in p.scientific_name.lower()
            or term in p.description.lower()
        ]

    if enrich:
        perenual = get_perenual_service()
        plants = await perenual.enrich_plants(plants, max_lookups=10)

    logger.info(
        "Catalog: %d results (type=%s sun=%s season=%s region=%s search=%s enrich=%s)",
        len(plants), type, sun, season, region, search, enrich,
    )
    return plants


@router.get("/engine-status")
async def get_engine_status(user_id: str = Depends(get_current_user)):
    """Return availability status of each recommendation engine."""
    statuses = {}

    # Check Gemini
    if not settings.gemini_api_key:
        statuses["gemini"] = {"available": False, "reason": "No Gemini API key configured"}
    else:
        try:
            import google.generativeai as genai
            genai.configure(api_key=settings.gemini_api_key)
            statuses["gemini"] = {"available": True, "reason": "Gemini 2.5 Flash Lite (cloud AI)"}
        except Exception as e:
            statuses["gemini"] = {"available": False, "reason": f"Gemini error: {str(e)[:80]}"}

    # Check Ollama — use configured model name (settings.ollama_model) so the
    # check passes regardless of which model the user has installed.
    configured_model = getattr(settings, "ollama_model", "gemma3:1b")
    # Normalise for comparison: strip tag (e.g. "gemma3:1b" → "gemma3")
    configured_base = configured_model.split(":")[0].lower()
    try:
        import httpx as _httpx
        ollama_url = getattr(settings, "ollama_url", "http://localhost:11434")
        async with _httpx.AsyncClient(timeout=3.0) as client:
            resp = await client.get(f"{ollama_url}/api/tags")
            if resp.status_code == 200:
                models = resp.json().get("models", [])
                model_names = [m.get("name", "").lower() for m in models]
                # Check for any installed model whose name starts with the configured base.
                matched = [n for n in model_names if n.startswith(configured_base)]
                if matched:
                    statuses["ollama"] = {
                        "available": True,
                        "reason": f"Using {matched[0]} via Ollama (local AI, offline)",
                    }
                else:
                    installed = ", ".join(model_names) or "none"
                    statuses["ollama"] = {
                        "available": False,
                        "reason": (
                            f"Ollama running but '{configured_model}' not installed. "
                            f"Installed: {installed}. Run: ollama pull {configured_model}"
                        ),
                    }
            else:
                statuses["ollama"] = {
                    "available": False,
                    "reason": "Ollama server not responding",
                }
    except Exception:
        statuses["ollama"] = {
            "available": False,
            "reason": f"Ollama not running. Install from ollama.ai and run: ollama serve && ollama pull {configured_model}",
        }

    statuses["rules"] = {"available": True, "reason": "Built-in rules (always available, works offline)"}
    return statuses


@router.get("/{plant_id}", response_model=Plant)
async def get_plant(
    plant_id: str,
    enrich: bool = Query(False, description="Enrich with Perenual image"),
    user_id: str = Depends(get_current_user),
):
    """Return a single plant by its ID, optionally Perenual-enriched."""
    recommender = get_plant_recommender()
    plant = recommender.plants.get(plant_id)
    if plant is None:
        raise HTTPException(status_code=404, detail=f"Plant '{plant_id}' not found")

    perenual = get_perenual_service() if enrich else None
    if enrich and perenual and (
        plant.image_url is None
        or perenual.uses_legacy_image_source(plant.image_url)
    ):
        data = await perenual.search_plant(
            name=plant.name,
            scientific_name=plant.scientific_name,
        )
        if data and data.get("image_url"):
            plant = plant.model_copy(update={
                "image_url": data["image_url"],
                "perenual_id": data.get("perenual_id"),
            })

    return plant


@router.post("/recommend", response_model=RecommendResponse)
async def recommend_plants(
    body: RecommendRequest,
    user_id: str = Depends(get_current_user),
):
    """Generate scored plant recommendations, enriched with Perenual images.

    Engine priority:
      1. Gemini 2.5 Flash Lite (cloud — free tier, needs internet)
      2. Ollama (local LLM — free, offline, no quota)
      3. Rule-based weighted algorithm (always works)
    Results are then enriched with Perenual plant images.
    """
    recommender = get_plant_recommender()
    result, engine, requested, fallback = await _run_engine_chain(
        body, recommender, get_gemini_recommender(), get_ollama_recommender(),
    )

    # Enrich with Perenual images
    perenual = get_perenual_service()
    enriched_plants = await perenual.enrich_plants(
        [r.plant for r in result.recommendations],
        max_lookups=10,
    )
    result.recommendations = [
        rec.model_copy(update={"plant": enriched_plants[i]})
        for i, rec in enumerate(result.recommendations)
    ]

    logger.info(
        "Recommend [%s → %s]: %d results for month=%d sun=%s region=%s exp=%s",
        requested or "auto", engine, result.total,
        body.month, body.bed_sunlight, body.region, body.experience_level,
    )
    result.engine_used = engine
    result.engine_requested = requested
    result.fallback_reason = fallback
    return result
