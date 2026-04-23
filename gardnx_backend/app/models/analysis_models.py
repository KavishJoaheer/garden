"""Pydantic models for garden analysis, segmentation, and photo uploads."""

from pydantic import BaseModel, Field
from typing import List, Literal, Optional


class Point(BaseModel):
    """A 2D point with normalized coordinates (0-1)."""

    x: float = Field(..., ge=0.0, le=1.0, description="Normalized x coordinate")
    y: float = Field(..., ge=0.0, le=1.0, description="Normalized y coordinate")


class ZoneInfo(BaseModel):
    """A detected zone in the garden image."""

    zone_id: str
    type: str  # soil, lawn, path, shade, existing_plant
    confidence: float = Field(..., ge=0.0, le=1.0)
    polygon: List[Point]
    area_sq_meters: float = Field(..., ge=0.0)


class SegmentationResponse(BaseModel):
    """Response containing segmentation results."""

    segmentation_id: str
    zones: List[ZoneInfo]
    mask_url: Optional[str] = None
    processing_time_ms: int
    fallback_recommended: bool = False
    segmentationSource: Literal["mock", "hf", "pil"] = "mock"


class PhotoUploadResponse(BaseModel):
    """Response after uploading a garden photo.

    Field names match Flutter's GardenPhoto.fromJson: ``id`` and ``imageUrl``.
    """

    id: str
    imageUrl: str
    width: int
    height: int


class SelectedArea(BaseModel):
    """A rectangular selected area on the image."""

    top_left: Point
    bottom_right: Point


class SegmentationRequest(BaseModel):
    """Request body for segmentation with optional area selection."""

    selected_area: Optional[SelectedArea] = None
