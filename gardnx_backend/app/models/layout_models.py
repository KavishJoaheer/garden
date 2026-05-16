"""Pydantic models for garden layout planning."""

from pydantic import BaseModel, Field


class BedInfo(BaseModel):
    """Garden bed dimensions and conditions."""

    width_cm: float = Field(..., gt=0, description="Bed width in centimeters")
    height_cm: float = Field(..., gt=0, description="Bed height/length in centimeters")
    sun_exposure: str = Field(
        default="full_sun",
        description="Sun exposure: full_sun, partial_shade, full_shade",
    )
    soil_type: str = Field(default="loamy", description="Soil type")


class GridCell(BaseModel):
    """A single cell in the garden layout grid."""

    row: int
    col: int
    plant_id: str | None = None
    is_occupied: bool = False
    is_border: bool = False


class PlantPlacement(BaseModel):
    """A plant placement on the layout grid."""

    plant_id: str = Field(..., description="ID of the plant to place")
    plant_name: str = Field(default="", description="Display name of the plant")
    row: int = Field(..., ge=0, description="Starting row in the grid")
    col: int = Field(..., ge=0, description="Starting column in the grid")
    span_rows: int = Field(default=1, ge=1, description="Number of rows this plant spans")
    span_cols: int = Field(default=1, ge=1, description="Number of columns this plant spans")
    count: int = Field(default=1, ge=1, description="Number of plants in this cell group")


class SelectedPlant(BaseModel):
    """A plant selected by the user for layout generation."""

    plant_id: str
    quantity: int = Field(default=1, ge=1, description="Desired number of this plant")
    priority: int = Field(
        default=5, ge=1, le=10, description="Placement priority (1=highest)"
    )


class LayoutRequest(BaseModel):
    """Request to generate a garden layout."""

    bed: BedInfo
    plants: list[SelectedPlant]
    use_companion_rules: bool = Field(
        default=True, description="Apply companion planting rules"
    )


class LayoutStatistics(BaseModel):
    """Statistics about the generated layout."""

    total_cells: int = 0
    occupied_cells: int = 0
    utilization_percent: float = 0.0
    plants_placed: int = 0
    plants_requested: int = 0
    grid_rows: int = 0
    grid_cols: int = 0
    cell_size_cm: float = 0.0


class LayoutResponse(BaseModel):
    """Response with generated garden layout."""

    placements: list[PlantPlacement]
    grid: list[list[str | None]] = Field(
        default_factory=list,
        description="2D grid representation where each cell has plant_id or None",
    )
    statistics: LayoutStatistics
    warnings: list[str] = Field(default_factory=list)
    bed: BedInfo


class LayoutWarning(BaseModel):
    """A warning about the garden layout."""

    type: str = Field(
        ...,
        description="Warning type: companion_conflict, spacing_issue, sun_mismatch",
    )
    message: str
    plant1_id: str | None = None
    plant2_id: str | None = None
    severity: str = Field(
        default="warning", description="Severity: info, warning, error"
    )


class ValidationRequest(BaseModel):
    """Request to validate a user-created layout."""

    bed: BedInfo
    placements: list[PlantPlacement]


class ValidationResponse(BaseModel):
    """Response with layout validation results."""

    is_valid: bool
    warnings: list[LayoutWarning]
    total_warnings: int
    total_errors: int


class SpacingRequest(BaseModel):
    """Request to calculate max plants for a bed."""

    bed_width_cm: float = Field(..., gt=0)
    bed_height_cm: float = Field(..., gt=0)
    between_plants_cm: float = Field(..., gt=0)
    between_rows_cm: float = Field(..., gt=0)


class SpacingResponse(BaseModel):
    """Response with spacing calculation."""

    max_plants: int
    rows: int
    cols: int
    actual_between_plants_cm: float
    actual_between_rows_cm: float
    bed_utilization_percent: float


class RecommendBedRequest(BaseModel):
    """Request for plant recommendations for a specific garden bed."""

    garden_id: str = ""
    bed_id: str = ""
    width_cm: float = Field(..., gt=0)
    height_cm: float = Field(..., gt=0)
    sun_exposure: str = Field(default="full_sun")
    soil_type: str = Field(default="loamy")
    season: str = Field(default="summer")
    region: str = Field(default="north")
    preferences: list[str] = Field(default_factory=list)
    experience_level: str | None = Field(default=None)
    preferred_engine: str | None = Field(default=None)


class BedSuggestion(BaseModel):
    """A single plant recommendation for a bed."""

    plant_id: str
    plant_name: str
    suitability_score: float
    reasons: list[str]
    companion_names: list[str] = []
    max_count: int


class RecommendBedResponse(BaseModel):
    """Response with plant recommendations for a bed."""

    recommendations: list[BedSuggestion]
    engine_used: str = "rules"
    engine_requested: str | None = None
    fallback_reason: str | None = None
    ai_reasoning: str | None = None
