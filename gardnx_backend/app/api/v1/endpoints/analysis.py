"""Garden photo analysis endpoints: upload, segment, and retrieve results."""

import hashlib
import json
import logging
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse

from app.api.deps import get_current_user, get_analyzer
from app.config import settings
from app.models.analysis_models import (
    PhotoUploadResponse,
    SegmentationRequest,
    SegmentationResponse,
)
from app.services.garden_analyzer import GardenAnalyzer
from app.utils.image_utils import compress_image, get_image_dimensions

logger = logging.getLogger("gardnx")
router = APIRouter()

_ALLOWED_MIME = {"image/jpeg", "image/jpg", "image/png", "image/webp"}
_MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # 10 MB


def _user_dir(user_id: str) -> Path:
    d = Path(settings.photo_storage_path) / (user_id or "anonymous")
    d.mkdir(parents=True, exist_ok=True)
    return d


def _photo_path(user_id: str, photo_id: str) -> Path:
    return _user_dir(user_id) / f"{photo_id}.bin"


def _meta_path(user_id: str, photo_id: str) -> Path:
    return _user_dir(user_id) / f"{photo_id}.meta.json"


def _result_path(user_id: str, photo_id: str) -> Path:
    return _user_dir(user_id) / f"{photo_id}.result.json"


def _find_by_hash(user_id: str, sha: str) -> str | None:
    """Return an existing photo_id for [user_id] whose bytes hash to [sha]."""
    for meta_file in _user_dir(user_id).glob("*.meta.json"):
        try:
            meta = json.loads(meta_file.read_text())
            if meta.get("sha256") == sha:
                return meta.get("photo_id")
        except (OSError, json.JSONDecodeError):
            continue
    return None


@router.post("/upload", response_model=PhotoUploadResponse)
async def upload_photo(
    file: UploadFile = File(...),
    user_id: str = Depends(get_current_user),
):
    """Upload a garden photo. Bytes are persisted under
    `{photo_storage_path}/{user_id}/{photo_id}.bin` with a sibling
    `.meta.json`. Re-uploading identical bytes returns the prior photo_id.
    """
    if not file.content_type or file.content_type.lower() not in _ALLOWED_MIME:
        raise HTTPException(
            status_code=400,
            detail=f"Content-Type must be one of {sorted(_ALLOWED_MIME)}",
        )

    image_bytes = await file.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="Empty file")
    if len(image_bytes) > _MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"File exceeds {_MAX_UPLOAD_BYTES // (1024 * 1024)} MB limit",
        )

    compressed = compress_image(image_bytes, max_size=1920, quality=85)
    sha = hashlib.sha256(compressed).hexdigest()

    existing = _find_by_hash(user_id, sha)
    if existing is not None:
        meta = json.loads(_meta_path(user_id, existing).read_text())
        return PhotoUploadResponse(
            id=existing,
            imageUrl=f"/api/v1/analysis/photo/{existing}",
            width=meta["width"],
            height=meta["height"],
        )

    width, height = get_image_dimensions(compressed)
    photo_id = str(uuid.uuid4())
    _photo_path(user_id, photo_id).write_bytes(compressed)
    _meta_path(user_id, photo_id).write_text(
        json.dumps({
            "photo_id": photo_id,
            "user_id": user_id,
            "content_type": file.content_type,
            "width": width,
            "height": height,
            "bytes": len(compressed),
            "sha256": sha,
        })
    )

    logger.info(
        "Photo uploaded: id=%s user=%s size=%dx%d bytes=%d",
        photo_id, user_id, width, height, len(compressed),
    )

    return PhotoUploadResponse(
        id=photo_id,
        imageUrl=f"/api/v1/analysis/photo/{photo_id}",
        width=width,
        height=height,
    )


@router.get("/photo/{photo_id}")
async def get_photo(
    photo_id: str,
    user_id: str = Depends(get_current_user),
):
    """Serve the raw photo bytes for [photo_id].

    Only the uploader can read their own photos.
    """
    path = _photo_path(user_id, photo_id)
    if not path.exists():
        raise HTTPException(status_code=404, detail=f"Photo {photo_id} not found")
    meta_path = _meta_path(user_id, photo_id)
    media_type = "image/jpeg"
    if meta_path.exists():
        try:
            media_type = json.loads(meta_path.read_text()).get(
                "content_type", "image/jpeg"
            )
        except (OSError, json.JSONDecodeError):
            pass
    return FileResponse(path, media_type=media_type)


@router.post("/segment/{photo_id}", response_model=SegmentationResponse)
async def segment_photo(
    photo_id: str,
    body: SegmentationRequest | None = None,
    user_id: str = Depends(get_current_user),
    analyzer: GardenAnalyzer = Depends(get_analyzer),
):
    """Run segmentation on a previously uploaded photo.

    Accepts an optional SegmentationRequest body to specify a
    selected area. Returns detected zones with confidence scores.
    """
    path = _photo_path(user_id, photo_id)
    if not path.exists():
        raise HTTPException(status_code=404, detail=f"Photo {photo_id} not found")
    image_bytes = path.read_bytes()

    selected_area = body.selected_area if body else None
    result = analyzer.analyze(image_bytes, selected_area=selected_area)

    _result_path(user_id, photo_id).write_text(result.model_dump_json())

    logger.info(
        "Segmentation complete: photo=%s zones=%d source=%s time=%dms",
        photo_id,
        len(result.zones),
        result.segmentationSource,
        result.processing_time_ms,
    )

    return result


@router.get("/result/{photo_id}", response_model=SegmentationResponse)
async def get_result(
    photo_id: str,
    user_id: str = Depends(get_current_user),
):
    """Retrieve cached segmentation result for a photo."""
    path = _result_path(user_id, photo_id)
    if not path.exists():
        raise HTTPException(
            status_code=404,
            detail=f"No analysis result found for photo {photo_id}. Run /segment first.",
        )
    return SegmentationResponse.model_validate_json(path.read_text())
