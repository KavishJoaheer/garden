"""Pydantic models for plant-related data."""

from typing import Literal

from pydantic import BaseModel, Field

ExperienceLevel = Literal["beginner", "intermediate", "advanced"]


class PlantConditions(BaseModel):
    """Growing conditions for a plant."""

    sunlight: str = Field(
        ..., description="Sun requirement: full_sun, partial_shade, full_shade"
    )
    min_temp_c: float = Field(..., description="Minimum temperature in Celsius")
    max_temp_c: float = Field(..., description="Maximum temperature in Celsius")
    soil_types: list[str] = Field(
        ..., description="Suitable soil types: loamy, sandy, clay, well_drained, rich"
    )
    water_needs: str = Field(..., description="Water needs: low, moderate, high")
    ph_min: float = Field(default=5.5, description="Minimum soil pH")
    ph_max: float = Field(default=7.5, description="Maximum soil pH")


class PlantSpacing(BaseModel):
    """Spacing requirements for a plant."""

    between_plants_cm: float = Field(..., description="Space between plants in cm")
    between_rows_cm: float = Field(..., description="Space between rows in cm")
    plant_width_cm: float = Field(..., description="Mature plant width in cm")
    plant_height_cm: float = Field(..., description="Mature plant height in cm")


class PlantTiming(BaseModel):
    """Planting and harvest timing."""

    sowing_months: list[int] = Field(
        ..., description="Months suitable for sowing (1-12)"
    )
    transplant_months: list[int] = Field(
        default_factory=list, description="Months suitable for transplanting (1-12)"
    )
    harvest_months: list[int] = Field(
        ..., description="Months when harvest is possible (1-12)"
    )
    days_to_germination: int = Field(..., description="Days from sowing to germination")
    days_to_harvest: int = Field(..., description="Days from sowing to harvest")


class Plant(BaseModel):
    """Full plant model matching Firestore schema."""

    id: str
    name: str
    name_fr: str = ""
    scientific_name: str = ""
    type: str = Field(
        ..., description="Plant type: vegetable, herb, fruit, flower, tree"
    )
    conditions: PlantConditions
    spacing: PlantSpacing
    timing: PlantTiming
    mauritius_regions: list[str] = Field(
        default_factory=lambda: ["north", "south", "east", "west", "central"],
        description="Regions of Mauritius where plant grows well",
    )
    companion_plants: list[str] = Field(
        default_factory=list, description="IDs of companion plants"
    )
    incompatible_plants: list[str] = Field(
        default_factory=list, description="IDs of incompatible plants"
    )
    description: str = ""
    care_notes: str = ""
    # Enriched by Perenual API
    image_url: str | None = Field(default=None, description="Plant image from Perenual API")
    perenual_id: int | None = Field(default=None, description="Perenual species ID")


class PlantRecommendation(BaseModel):
    """A scored plant recommendation."""

    plant: Plant
    score: float = Field(..., ge=0.0, le=1.0, description="Overall recommendation score")
    reasons: list[str] = Field(..., description="Human-readable reasons for recommendation")
    sun_score: float = 0.0
    season_score: float = 0.0
    temp_score: float = 0.0
    region_score: float = 0.0
    preference_score: float = 0.0


class PlantFilter(BaseModel):
    """Filters for plant catalog queries."""

    type: str | None = Field(default=None, description="Filter by plant type")
    sunlight: str | None = Field(default=None, description="Filter by sun requirement")
    season: str | None = Field(
        default=None, description="Filter by current season suitability"
    )
    region: str | None = Field(default=None, description="Filter by Mauritius region")
    search: str | None = Field(default=None, description="Search term for name")


class CompanionRule(BaseModel):
    """A companion planting rule."""

    plant1_id: str
    plant2_id: str
    relationship: str = Field(
        ..., description="Relationship type: companion, incompatible"
    )
    reason: str = Field(default="", description="Reason for the relationship")


class RecommendRequest(BaseModel):
    """Request for plant recommendations."""

    bed_sunlight: str = Field(
        ..., description="Bed sun exposure: full_sun, partial_shade, full_shade"
    )
    bed_soil_type: str = Field(default="loamy", description="Bed soil type")
    latitude: float = Field(default=-20.2, description="Location latitude")
    longitude: float = Field(default=57.5, description="Location longitude")
    month: int = Field(..., ge=1, le=12, description="Current or target month")
    region: str = Field(default="north", description="Mauritius region")
    current_temp_c: float | None = Field(
        default=None, description="Current temperature in Celsius"
    )
    preferences: list[str] = Field(
        default_factory=list,
        description="User preferences: e.g., ['vegetables', 'low_maintenance', 'fast_growing']",
    )
    exclude_plant_ids: list[str] = Field(
        default_factory=list, description="Plant IDs to exclude"
    )
    preferred_engine: str | None = Field(
        default=None, description="Preferred AI engine: gemini, ollama, or rules"
    )
    experience_level: ExperienceLevel | None = Field(
        default=None,
        description="Gardener experience — beginner filters out difficult plants",
    )


class RecommendResponse(BaseModel):
    """Response with plant recommendations."""

    recommendations: list[PlantRecommendation]
    total: int
    filters_applied: dict = {}
    engine_used: str = "rules"
    engine_requested: str | None = None
    fallback_reason: str | None = None
