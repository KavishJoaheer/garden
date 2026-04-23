"""Seed script to populate Firestore with the GardNx plant database.

Usage:
    python scripts/seed_database.py

Prerequisites:
    - Set FIREBASE_CREDENTIALS_PATH env var (or place credentials at
      ./firebase-credentials.json)
    - pip install firebase-admin
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Add project root to sys.path so we can import from app/
# ---------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import firebase_admin
from firebase_admin import credentials, firestore

from app.config import settings
from app.services.perenual_service import PerenualService


# ---------------------------------------------------------------------------
# Firebase initialisation
# ---------------------------------------------------------------------------

def _init_firebase() -> None:
    creds_path = os.environ.get(
        "FIREBASE_CREDENTIALS_PATH",
        str(ROOT / "firebase-credentials.json"),
    )
    if not Path(creds_path).exists():
        print(f"[ERROR] Firebase credentials not found at {creds_path}")
        print("  Set FIREBASE_CREDENTIALS_PATH or place the file at firebase-credentials.json")
        sys.exit(1)

    cred = credentials.Certificate(creds_path)
    firebase_admin.initialize_app(cred)
    print(f"[OK] Firebase initialised from {creds_path}")


# ---------------------------------------------------------------------------
# Data transformation helpers
#
# The backend plants_mauritius.json uses the Python/API schema.
# Firestore (and the Flutter app) uses a slightly different schema.
# This function converts between the two.
# ---------------------------------------------------------------------------

_SUNLIGHT_MAP = {
    "full_sun": "full_sun",
    "partial_shade": "partial_shade",
    "full_shade": "full_shade",
}

_CATEGORY_MAP = {
    "vegetable": "vegetable",
    "herb": "herb",
    "fruit": "fruit",
    "flower": "flower",
    "tree": "tree",
}

_LEGACY_IMAGE_HOSTS = (
    "upload.wikimedia.org",
    "commons.wikimedia.org",
    "wikipedia.org",
)


def _normalize_image_url(image_url: str | None) -> str | None:
    """Drop old Wikipedia/Wikimedia image URLs during Firestore seeding."""
    if not image_url:
        return None
    image_url_lower = image_url.lower()
    if any(host in image_url_lower for host in _LEGACY_IMAGE_HOSTS):
        return None
    return image_url


def _to_firestore_plant(p: dict) -> dict:
    """Convert a backend-schema plant dict to the Flutter/Firestore schema."""
    conds = p.get("conditions", {})
    spacing = p.get("spacing", {})
    timing = p.get("timing", {})

    return {
        # ---- Identity ----
        "name": p["name"],
        "scientific_name": p.get("scientific_name", ""),
        "category": _CATEGORY_MAP.get(p.get("type", "vegetable"), "vegetable"),
        "description": p.get("description", ""),
        "care_notes": p.get("care_notes", ""),
        "image_url": _normalize_image_url(p.get("image_url")),

        # ---- Conditions ----
        "conditions": {
            "min_temp_c": conds.get("min_temp_c", 15.0),
            "max_temp_c": conds.get("max_temp_c", 35.0),
            "sun_requirement": _SUNLIGHT_MAP.get(conds.get("sunlight", "full_sun"), "full_sun"),
            "water_needs": conds.get("water_needs", "moderate"),
            "suitable_soils": conds.get("soil_types", ["loam"]),
            "min_humidity": 40.0,
            "max_humidity": 90.0,
        },

        # ---- Spacing ----
        "spacing": {
            "plant_spacing_cm": spacing.get("between_plants_cm", 30.0),
            "row_spacing_cm": spacing.get("between_rows_cm", 30.0),
            "grid_cells_required": _estimate_grid_cells(spacing),
        },

        # ---- Timing ----
        "timing": {
            "sow_months": timing.get("sowing_months", []),
            "transplant_months": timing.get("transplant_months", []),
            "harvest_months": timing.get("harvest_months", []),
            "days_to_maturity": timing.get("days_to_harvest", 60),
            "days_to_transplant": timing.get("days_to_germination", 7) + 14,
        },

        # ---- Companion planting ----
        "companion_plant_ids": p.get("companion_plants", []),
        "incompatible_plant_ids": p.get("incompatible_plants", []),

        # ---- Meta ----
        "mauritius_regions": p.get("mauritius_regions", ["north", "south", "east", "west", "central"]),
        "suitability_score": 0.85,
        "tags": _build_tags(p),
        "is_native": False,
        "difficulty_level": _estimate_difficulty(p),

        # ---- Ownership ----
        # userId=None marks curated/global plants visible to all authenticated
        # users under the split-query catalog read (Phase B).
        "userId": None,
    }


def _estimate_grid_cells(spacing: dict) -> int:
    """Estimate the number of grid cells a plant needs (1-4)."""
    w = spacing.get("plant_width_cm", 30)
    h = spacing.get("plant_height_cm", 30)
    area = w * h
    if area < 1000:   # < 10x10 cm
        return 1
    elif area < 4000: # < 63x63 cm
        return 1
    elif area < 9000: # < 95x95 cm
        return 2
    else:
        return 4


def _estimate_difficulty(p: dict) -> str:
    """Estimate difficulty level from plant characteristics."""
    timing = p.get("timing", {})
    days = timing.get("days_to_harvest", 60)
    water = p.get("conditions", {}).get("water_needs", "moderate")

    if days <= 45 and water in ("low", "moderate"):
        return "easy"
    elif days >= 150 or water == "high":
        return "hard"
    else:
        return "medium"


def _build_tags(p: dict) -> list[str]:
    """Build a list of searchable tags from plant attributes."""
    tags = [p.get("type", "vegetable")]
    timing = p.get("timing", {})
    days = timing.get("days_to_harvest", 60)
    water = p.get("conditions", {}).get("water_needs", "moderate")
    sunlight = p.get("conditions", {}).get("sunlight", "full_sun")

    if days <= 45:
        tags.append("fast_growing")
    if water == "low":
        tags.append("drought_tolerant")
    if sunlight == "partial_shade":
        tags.append("shade_tolerant")
    # Mauritius regions
    for region in p.get("mauritius_regions", []):
        tags.append(f"region_{region}")

    sowing = timing.get("sowing_months", [])
    if any(m in sowing for m in [11, 12, 1, 2, 3, 4]):
        tags.append("summer_crop")
    if any(m in sowing for m in [5, 6, 7, 8, 9, 10]):
        tags.append("winter_crop")

    return tags


async def enrich_plant_images_with_perenual(
    plants_data: list[dict],
    max_lookups: int | None = None,
) -> int:
    """Populate missing plant image URLs from Perenual before seeding."""
    perenual = PerenualService(api_key=settings.perenual_api_key)
    if not settings.perenual_api_key:
        print("[WARN] PERENUAL_API_KEY is missing. Skipping image enrichment.")
        return 0

    enriched_count = 0
    lookups_done = 0

    for plant in plants_data:
        current_image = _normalize_image_url(plant.get("image_url"))
        if current_image:
            plant["image_url"] = current_image
            continue

        if max_lookups is not None and lookups_done >= max_lookups:
            break

        data = await perenual.search_plant(
            name=plant.get("name", ""),
            scientific_name=plant.get("scientific_name", ""),
        )
        lookups_done += 1

        image_url = data.get("image_url") if data else None
        if image_url:
            plant["image_url"] = image_url
            enriched_count += 1
            print(f"  [IMG] {plant['id']}: image added")
        else:
            plant["image_url"] = None
            print(f"  [IMG] {plant['id']}: no image found")

    print(f"[OK] Perenual enrichment complete: {enriched_count} images added.")
    return enriched_count


def _to_firestore_companion_rule(r: dict, idx: int) -> tuple[str, dict]:
    """Convert a backend companion rule to Firestore schema."""
    rule_id = f"rule_{idx:04d}"
    return rule_id, {
        "plant_a_id": r["plant1_id"],
        "plant_b_id": r["plant2_id"],
        "type": r["type"],      # "companion" | "incompatible"
        "reason": r.get("reason", ""),
        "strength_score": 0.8,
    }


# ---------------------------------------------------------------------------
# Seeding functions
# ---------------------------------------------------------------------------

def seed_plants(db: firestore.Client, plants_data: list[dict], dry_run: bool = False) -> int:
    """Upload plant documents to the 'plants' Firestore collection."""
    collection = db.collection("plants")
    count = 0

    for p in plants_data:
        plant_id = p["id"]
        doc = _to_firestore_plant(p)

        if dry_run:
            print(f"  [DRY] Would write plants/{plant_id}: {p['name']}")
        else:
            collection.document(plant_id).set(doc)
            print(f"  [OK] plants/{plant_id}: {p['name']}")

        count += 1

    return count


def seed_companion_rules(
    db: firestore.Client, rules_data: list[dict], dry_run: bool = False
) -> int:
    """Upload companion rule documents to the 'companion_rules' collection."""
    collection = db.collection("companion_rules")
    count = 0

    for idx, r in enumerate(rules_data):
        rule_id, doc = _to_firestore_companion_rule(r, idx)

        if dry_run:
            print(f"  [DRY] Would write companion_rules/{rule_id}: {r['plant1_id']} <-> {r['plant2_id']} ({r['type']})")
        else:
            collection.document(rule_id).set(doc)
            print(f"  [OK] companion_rules/{rule_id}: {r['plant1_id']} <-> {r['plant2_id']} ({r['type']})")

        count += 1

    return count


def seed_mauritius_regions(db: firestore.Client, dry_run: bool = False) -> None:
    """Seed Mauritius region metadata."""
    data_file = ROOT / "app" / "data" / "mauritius_regions.json"
    if not data_file.exists():
        print("[SKIP] mauritius_regions.json not found")
        return

    with open(data_file) as f:
        regions = json.load(f)

    for region_id, region_data in regions.items():
        if dry_run:
            print(f"  [DRY] Would write regions/{region_id}")
        else:
            import time
            db.collection("regions").document(region_id).set(region_data)
            print(f"  [OK] regions/{region_id}")
            time.sleep(0.5)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Seed GardNx Firestore database")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be written without actually writing to Firestore",
    )
    parser.add_argument(
        "--plants-only",
        action="store_true",
        help="Only seed the plants collection",
    )
    parser.add_argument(
        "--rules-only",
        action="store_true",
        help="Only seed the companion_rules collection",
    )
    parser.add_argument(
        "--enrich-images",
        action="store_true",
        help="Fetch missing plant images from Perenual before seeding plants",
    )
    parser.add_argument(
        "--max-image-lookups",
        type=int,
        default=None,
        help="Optional cap on Perenual image lookups during --enrich-images",
    )
    args = parser.parse_args()

    dry_run: bool = args.dry_run

    # Load data files
    plants_path = ROOT / "app" / "data" / "plants_mauritius.json"
    rules_path = ROOT / "app" / "data" / "companion_rules.json"

    if not plants_path.exists():
        print(f"[ERROR] plants_mauritius.json not found at {plants_path}")
        sys.exit(1)

    if not rules_path.exists():
        print(f"[ERROR] companion_rules.json not found at {rules_path}")
        sys.exit(1)

    with open(plants_path) as f:
        plants_data: list[dict] = json.load(f)

    with open(rules_path) as f:
        rules_data: list[dict] = json.load(f)

    print(f"Loaded {len(plants_data)} plants and {len(rules_data)} companion rules.")
    print(f"Mode: {'DRY RUN' if dry_run else 'LIVE WRITE'}\n")

    if args.enrich_images and not args.rules_only:
        print("=== Enriching plant images from Perenual ===")
        asyncio.run(
            enrich_plant_images_with_perenual(
                plants_data,
                max_lookups=args.max_image_lookups,
            )
        )
        print()

    # Init Firebase
    _init_firebase()
    db = firestore.client()

    if not args.rules_only:
        print("=== Seeding plants ===")
        n = seed_plants(db, plants_data, dry_run=dry_run)
        print(f"Done: {n} plants {'(dry run)' if dry_run else 'written'}.\n")

    if not args.plants_only:
        print("=== Seeding companion rules ===")
        n = seed_companion_rules(db, rules_data, dry_run=dry_run)
        print(f"Done: {n} rules {'(dry run)' if dry_run else 'written'}.\n")

    if not args.plants_only and not args.rules_only:
        print("=== Seeding Mauritius regions ===")
        seed_mauritius_regions(db, dry_run=dry_run)
        print()

    print("Seeding complete!")


if __name__ == "__main__":
    main()
