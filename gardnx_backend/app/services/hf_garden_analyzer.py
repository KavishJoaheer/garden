"""Hugging Face Inference API garden zone segmentation.

Uses nvidia/segformer-b0-finetuned-ade-512-512 — a real semantic segmentation
CNN trained on ADE20K outdoor scenes.  No PyTorch install required: inference
runs remotely on Hugging Face's free CPU servers.

ADE20K labels → garden zone mapping is defined in ADE20K_TO_ZONE below.
"""

import base64
import io
import logging
import os
import time
import uuid
from typing import List, Optional

import httpx
from PIL import Image

from app.models.analysis_models import Point, SegmentationResponse, ZoneInfo

logger = logging.getLogger("gardnx")

HF_API_URL = (
    "https://router.huggingface.co/hf-inference/models/"
    "nvidia/segformer-b0-finetuned-ade-512-512"
)

# ADE20K label → GardNx zone type  (None = skip this class)
ADE20K_TO_ZONE: dict[str, Optional[str]] = {
    "grass":          "lawn",
    "earth":          "soil",
    "dirt":           "soil",
    "ground":         "soil",
    "sand":           "soil",
    "soil":           "soil",
    "plant":          "existing_plant",
    "flora":          "existing_plant",
    "tree":           "existing_plant",
    "palm":           "existing_plant",
    "shrub":          "existing_plant",
    "bush":           "existing_plant",
    "flower":         "existing_plant",
    "path":           "path",
    "sidewalk":       "path",
    "pavement":       "path",
    "road":           "path",
    "rock":           "path",
    "stone":          "path",
    "gravel":         "path",
    # shade is inferred from dark-pixel analysis after segmentation
    "sky":            None,
    "building":       None,
    "wall":           None,
    "fence":          None,
    "water":          None,
    "pool":           None,
    "person":         None,
    "animal":         None,
}


class HFGardenAnalyzer:
    """Calls Hugging Face Inference API for semantic segmentation.

    Parameters
    ----------
    api_token : str
        HF bearer token.  Can be empty string for anonymous (rate-limited).
    timeout : float
        HTTP timeout in seconds.  HF cold-starts can take ~20 s on free tier.
    """

    def __init__(self, api_token: str = "", timeout: float = 30.0):
        self.api_token = api_token
        self.timeout = timeout

    # ------------------------------------------------------------------
    def analyze(
        self,
        image_bytes: bytes,
        selected_area=None,
    ) -> Optional[SegmentationResponse]:
        """Return a SegmentationResponse or None if the API is unavailable."""
        start = time.time()

        # Crop to selected area first (same logic as colour analyzer)
        img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        if selected_area is not None:
            w, h = img.size
            left   = int(selected_area.top_left.x     * w)
            top    = int(selected_area.top_left.y     * h)
            right  = int(selected_area.bottom_right.x * w)
            bottom = int(selected_area.bottom_right.y * h)
            img = img.crop((left, top, right, bottom))

        # Re-encode as JPEG for the API call
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=85)
        payload = buf.getvalue()

        headers = {"Content-Type": "application/octet-stream"}
        if self.api_token:
            headers["Authorization"] = f"Bearer {self.api_token}"

        try:
            response = httpx.post(
                HF_API_URL,
                content=payload,
                headers=headers,
                timeout=self.timeout,
            )
            response.raise_for_status()
        except httpx.TimeoutException:
            logger.warning("HF API timeout after %.1fs", self.timeout)
            return None
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code == 503:
                logger.warning("HF model loading (503) — will fall back")
            else:
                logger.warning("HF API error %s", exc.response.status_code)
            return None
        except httpx.RequestError as exc:
            logger.warning("HF API request error: %s", exc)
            return None

        segments = response.json()
        if not isinstance(segments, list):
            logger.warning("Unexpected HF response: %s", type(segments))
            return None

        img_w, img_h = img.size
        zones = self._segments_to_zones(segments, img_w, img_h)

        if not zones:
            logger.info("HF segmentation returned 0 usable zones")
            return None

        ms = int((time.time() - start) * 1000)
        avg_conf = sum(z.confidence for z in zones) / len(zones)
        logger.info("HF segmentation: %d zones in %d ms", len(zones), ms)

        return SegmentationResponse(
            segmentation_id=str(uuid.uuid4()),
            zones=zones,
            processing_time_ms=ms,
            fallback_recommended=avg_conf < 0.5,
        )

    # ------------------------------------------------------------------
    def _segments_to_zones(
        self, segments: list, img_w: int, img_h: int
    ) -> List[ZoneInfo]:
        """Convert HF segmentation response to ZoneInfo list."""
        zones: List[ZoneInfo] = []
        zone_id = 1
        total_pixels = img_w * img_h

        for seg in segments:
            label_raw: str = seg.get("label", "").lower()
            score: float = float(seg.get("score", 0.75))

            # Map ADE20K label to garden zone
            zone_type = self._map_label(label_raw)
            if zone_type is None:
                continue

            # Decode the binary mask (HF returns base64-encoded PNG)
            mask_b64: str = seg.get("mask", "")
            if not mask_b64:
                continue
            mask_bytes = base64.b64decode(mask_b64)
            mask_img = Image.open(io.BytesIO(mask_bytes)).convert("L")
            mask_img = mask_img.resize((img_w, img_h), Image.NEAREST)

            # Compute bounding box of non-zero pixels
            bbox = mask_img.getbbox()  # (left, upper, right, lower) or None
            if bbox is None:
                continue

            left, upper, right, lower = bbox
            pixel_count = sum(1 for p in mask_img.getdata() if p > 128)

            # Filter tiny zones (< 3 % of image)
            if pixel_count < total_pixels * 0.03:
                continue

            x0, y0 = left / img_w, upper / img_h
            x1, y1 = right / img_w, lower / img_h
            area_frac = pixel_count / total_pixels
            area_sq_m = round(area_frac * 20.0, 2)
            confidence = round(min(score, 0.95), 2)

            zones.append(ZoneInfo(
                zone_id=f"z{zone_id}",
                type=zone_type,
                confidence=confidence,
                polygon=[
                    Point(x=x0, y=y0),
                    Point(x=x1, y=y0),
                    Point(x=x1, y=y1),
                    Point(x=x0, y=y1),
                ],
                area_sq_meters=area_sq_m,
            ))
            zone_id += 1

        # Merge zones of the same type into a single bounding box
        return self._merge_same_type(zones)

    def _map_label(self, label: str) -> Optional[str]:
        """Fuzzy-match an ADE20K label to a garden zone type."""
        # Direct match first
        if label in ADE20K_TO_ZONE:
            return ADE20K_TO_ZONE[label]
        # Substring match
        for key, zone in ADE20K_TO_ZONE.items():
            if key in label or label in key:
                return zone
        # Unknown outdoor label → treat as soil (plantable)
        return "soil"

    def _merge_same_type(self, zones: List[ZoneInfo]) -> List[ZoneInfo]:
        """Merge multiple zones of the same type into one bounding box."""
        merged: dict[str, ZoneInfo] = {}
        for z in zones:
            if z.type not in merged:
                merged[z.type] = z
            else:
                existing = merged[z.type]
                # Union of bounding boxes
                ex0 = min(existing.polygon[0].x, z.polygon[0].x)
                ey0 = min(existing.polygon[0].y, z.polygon[0].y)
                ex1 = max(existing.polygon[1].x, z.polygon[1].x)
                ey1 = max(existing.polygon[2].y, z.polygon[2].y)
                merged[z.type] = ZoneInfo(
                    zone_id=existing.zone_id,
                    type=existing.type,
                    confidence=round((existing.confidence + z.confidence) / 2, 2),
                    polygon=[
                        Point(x=ex0, y=ey0),
                        Point(x=ex1, y=ey0),
                        Point(x=ex1, y=ey1),
                        Point(x=ex0, y=ey1),
                    ],
                    area_sq_meters=round(existing.area_sq_meters + z.area_sq_meters, 2),
                )
        return list(merged.values())
