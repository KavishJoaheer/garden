"""Garden image analysis service.

Analysis priority:
1. HF Inference API  (USE_MOCK_MODEL=false, HF_API_TOKEN set or anonymous)
   → nvidia/segformer-b0-finetuned-ade-512-512 — real semantic segmentation CNN
2. PIL colour analysis (USE_MOCK_MODEL=false, HF unavailable/timeout)
   → HSV colour-zone detection, works offline
3. Mock (USE_MOCK_MODEL=true)
   → static hardcoded zones for fast development
"""

import io
import uuid
import time
import logging
from typing import List, Optional

from PIL import Image

from app.models.analysis_models import ZoneInfo, Point, SegmentationResponse

logger = logging.getLogger("gardnx")

# ── Colour thresholds for PIL fallback ─────────────────────────────────────
# Each entry: (H_min, H_max, S_min, S_max, V_min, V_max) — PIL HSV range 0-255

_ZONE_RULES = [
    # zone_type       H_lo  H_hi  S_lo  S_hi  V_lo  V_hi
    ("existing_plant", 40,  100,  50,   255,  40,   200),  # green
    ("lawn",           35,  100,  30,   255,  150,  255),  # bright green
    ("soil",           10,   45,  30,   200,  30,   180),  # brown / earth
    ("path",            0,  255,   0,    40,  140,  255),  # low saturation
    ("shade",           0,  255,   0,   255,   0,    70),  # very dark
]


class GardenAnalyzer:
    """Analyses garden photos to detect zones.

    Parameters
    ----------
    weights_path : str
        Unused — kept for API compatibility.
    use_mock : bool
        True  → return static hardcoded zones.
        False → try HF ML segmentation, fall back to PIL colour analysis.
    hf_api_token : str
        Hugging Face bearer token (can be empty for anonymous access).
    """

    def __init__(
        self,
        weights_path: str = "",
        use_mock: bool = True,
        hf_api_token: str = "",
    ):
        self.use_mock = use_mock
        self.weights_path = weights_path
        self.hf_api_token = hf_api_token
        self._loaded = False
        self._hf: Optional[object] = None

    def load_model(self) -> None:
        self._loaded = True
        if self.use_mock:
            logger.info("GardenAnalyzer: mock mode")
            return

        try:
            from app.services.hf_garden_analyzer import HFGardenAnalyzer
            self._hf = HFGardenAnalyzer(api_token=self.hf_api_token, timeout=30.0)
            logger.info("GardenAnalyzer: HF ML segmentation (SegFormer ADE20K) + PIL fallback")
        except ImportError:
            logger.warning("GardenAnalyzer: HF analyzer unavailable, PIL-only mode")

    def analyze(
        self,
        image_bytes: bytes,
        selected_area=None,
    ) -> SegmentationResponse:
        start_time = time.time()

        source: str
        if self.use_mock:
            zones = self._mock_analyze()
            source = "mock"
        else:
            zones, source = self._ml_analyze(image_bytes, selected_area)

        processing_time = int((time.time() - start_time) * 1000)
        avg_confidence = (
            sum(z.confidence for z in zones) / len(zones) if zones else 0
        )

        return SegmentationResponse(
            segmentation_id=str(uuid.uuid4()),
            zones=zones,
            processing_time_ms=processing_time,
            fallback_recommended=avg_confidence < 0.5,
            segmentationSource=source,  # type: ignore[arg-type]
        )

    # ------------------------------------------------------------------
    # ML pipeline: HF first, PIL fallback
    # ------------------------------------------------------------------

    def _ml_analyze(self, image_bytes: bytes, selected_area) -> tuple[List[ZoneInfo], str]:
        # 1. Try Hugging Face ML segmentation
        if self._hf is not None:
            try:
                result = self._hf.analyze(image_bytes, selected_area)
                if result and result.zones:
                    logger.info(
                        "HF ML segmentation succeeded: %d zones", len(result.zones)
                    )
                    return result.zones, "hf"
            except Exception as exc:
                logger.warning("HF analyzer raised %s — falling back to PIL", exc)

        # 2. PIL colour fallback
        logger.info("Using PIL colour-analysis fallback")
        return self._colour_analyze(image_bytes, selected_area), "pil"

    # ------------------------------------------------------------------
    # PIL colour-analysis pipeline (offline fallback)
    # ------------------------------------------------------------------

    def _colour_analyze(self, image_bytes: bytes, selected_area) -> List[ZoneInfo]:
        """Classify garden zones from colour/brightness using PIL only."""
        img = Image.open(io.BytesIO(image_bytes)).convert("RGB")

        if selected_area is not None:
            w, h = img.size
            left   = int(selected_area.top_left.x     * w)
            top    = int(selected_area.top_left.y     * h)
            right  = int(selected_area.bottom_right.x * w)
            bottom = int(selected_area.bottom_right.y * h)
            img = img.crop((left, top, right, bottom))

        GRID = 10
        thumb_w, thumb_h = 100, 100
        thumb = img.resize((thumb_w, thumb_h), Image.LANCZOS)
        hsv = thumb.convert("HSV")
        pixels = list(hsv.getdata())

        cell_w = thumb_w // GRID
        cell_h = thumb_h // GRID

        grid_labels = []
        for row in range(GRID):
            for col in range(GRID):
                cell_pixels = []
                for r in range(row * cell_h, (row + 1) * cell_h):
                    for c in range(col * cell_w, (col + 1) * cell_w):
                        cell_pixels.append(pixels[r * thumb_w + c])
                label = self._classify_cell(cell_pixels)
                grid_labels.append((row, col, label))

        return self._merge_cells_to_zones(grid_labels, GRID, GRID)

    def _classify_cell(self, pixels: List[tuple]) -> str:
        counts: dict[str, int] = {}
        for h, s, v in pixels:
            label = self._classify_pixel(h, s, v)
            counts[label] = counts.get(label, 0) + 1
        return max(counts, key=counts.get)

    def _classify_pixel(self, h: int, s: int, v: int) -> str:
        for zone_type, h_lo, h_hi, s_lo, s_hi, v_lo, v_hi in _ZONE_RULES:
            if h_lo <= h <= h_hi and s_lo <= s <= s_hi and v_lo <= v <= v_hi:
                return zone_type
        return "soil"

    def _merge_cells_to_zones(
        self, grid_labels: List[tuple], rows: int, cols: int
    ) -> List[ZoneInfo]:
        label_grid: list[list[str]] = [
            ["soil"] * cols for _ in range(rows)
        ]
        for r, c, label in grid_labels:
            label_grid[r][c] = label

        visited: list[list[bool]] = [[False] * cols for _ in range(rows)]
        zones: List[ZoneInfo] = []
        zone_id = 1

        for r in range(rows):
            for c in range(cols):
                if visited[r][c]:
                    continue
                label = label_grid[r][c]
                min_r, max_r, min_c, max_c = r, r, c, c
                queue = [(r, c)]
                visited[r][c] = True
                cell_count = 0
                while queue:
                    cr, cc = queue.pop()
                    cell_count += 1
                    min_r, max_r = min(min_r, cr), max(max_r, cr)
                    min_c, max_c = min(min_c, cc), max(max_c, cc)
                    for dr, dc in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
                        nr, nc = cr + dr, cc + dc
                        if (0 <= nr < rows and 0 <= nc < cols
                                and not visited[nr][nc]
                                and label_grid[nr][nc] == label):
                            visited[nr][nc] = True
                            queue.append((nr, nc))

                if cell_count < max(1, rows * cols // 25):
                    continue

                x0 = min_c / cols
                y0 = min_r / rows
                x1 = (max_c + 1) / cols
                y1 = (max_r + 1) / rows

                area_frac = cell_count / (rows * cols)
                area_sq_m = round(area_frac * 20.0, 2)
                confidence = round(min(0.60 + area_frac * 1.5, 0.95), 2)

                zones.append(ZoneInfo(
                    zone_id=f"z{zone_id}",
                    type=label,
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

        logger.info("PIL colour analysis: %d zones detected", len(zones))
        return zones if zones else self._mock_analyze()

    # ------------------------------------------------------------------
    # Mock pipeline
    # ------------------------------------------------------------------

    def _mock_analyze(self) -> List[ZoneInfo]:
        return [
            ZoneInfo(
                zone_id="z1", type="soil", confidence=0.92,
                polygon=[
                    Point(x=0.15, y=0.10), Point(x=0.85, y=0.10),
                    Point(x=0.85, y=0.55), Point(x=0.15, y=0.55),
                ],
                area_sq_meters=6.0,
            ),
            ZoneInfo(
                zone_id="z2", type="lawn", confidence=0.88,
                polygon=[
                    Point(x=0.00, y=0.55), Point(x=1.00, y=0.55),
                    Point(x=1.00, y=0.78), Point(x=0.00, y=0.78),
                ],
                area_sq_meters=3.5,
            ),
            ZoneInfo(
                zone_id="z3", type="path", confidence=0.85,
                polygon=[
                    Point(x=0.35, y=0.78), Point(x=0.65, y=0.78),
                    Point(x=0.65, y=1.00), Point(x=0.35, y=1.00),
                ],
                area_sq_meters=1.2,
            ),
            ZoneInfo(
                zone_id="z4", type="shade", confidence=0.72,
                polygon=[
                    Point(x=0.00, y=0.00), Point(x=0.15, y=0.00),
                    Point(x=0.15, y=0.55), Point(x=0.00, y=0.55),
                ],
                area_sq_meters=1.8,
            ),
            ZoneInfo(
                zone_id="z5", type="existing_plant", confidence=0.78,
                polygon=[
                    Point(x=0.85, y=0.00), Point(x=1.00, y=0.00),
                    Point(x=1.00, y=0.30), Point(x=0.85, y=0.30),
                ],
                area_sq_meters=0.9,
            ),
        ]
