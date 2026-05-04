"""Climate and weather data endpoints for Mauritius."""

import logging

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from typing import List

from app.api.deps import get_current_user
from app.dependencies import get_climate_service as _get_climate_service
from app.services.climate_service import ClimateService

logger = logging.getLogger("gardnx")
router = APIRouter()


# --- Response models ---

class CurrentClimateResponse(BaseModel):
    """Current climate conditions at a location."""
    temperature_c: float
    humidity_percent: float
    wind_speed_kmh: float
    precipitation_mm: float
    season: str
    sub_season: str
    gardening_notes: str


class MonthlyAverage(BaseModel):
    """Average climate data for a single month."""
    month: int = Field(..., ge=1, le=12)
    month_name: str
    avg_temp_c: float
    min_temp_c: float
    max_temp_c: float
    avg_rainfall_mm: float
    avg_humidity_percent: float
    season: str
    is_planting_season: bool


class MonthlyClimateResponse(BaseModel):
    """12-month climate averages for a location."""
    latitude: float
    longitude: float
    months: List[MonthlyAverage]


# --- Endpoints ---

@router.get("/current", response_model=CurrentClimateResponse)
async def get_current_climate(
    lat: float = Query(..., ge=-90, le=90, description="Latitude"),
    lon: float = Query(..., ge=-180, le=180, description="Longitude"),
    user_id: str = Depends(get_current_user),
):
    """Return current climate conditions and Mauritius season info.

    Fetches real-time weather from Open-Meteo API with a 24-hour cache.
    Falls back to historical averages if the API is unreachable.
    """
    service = _get_climate_service()
    data = await service.fetch_current_climate(lat, lon)

    logger.info("Climate current: lat=%.2f lon=%.2f temp=%.1fC season=%s",
                lat, lon, data["temperature_c"], data["season"])

    return CurrentClimateResponse(**data)


@router.get("/monthly", response_model=MonthlyClimateResponse)
async def get_monthly_averages(
    lat: float = Query(..., ge=-90, le=90, description="Latitude"),
    lon: float = Query(..., ge=-180, le=180, description="Longitude"),
    user_id: str = Depends(get_current_user),
):
    """Return 12-month average climate data for the given location.

    Uses Open-Meteo historical archive with caching. Includes season
    labels and planting-season flags for each month.
    """
    service = _get_climate_service()
    months = await service.fetch_monthly_averages(lat, lon)

    logger.info("Climate monthly: lat=%.2f lon=%.2f months=%d", lat, lon, len(months))

    return MonthlyClimateResponse(
        latitude=lat,
        longitude=lon,
        months=months,
    )
