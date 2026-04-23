"""One-shot Firestore schema migration for gardnx.

Canonical schema is camelCase. Legacy docs (snake_case fields, missing
`userId` on events/tasks, stale embedded `id` on beds, missing `bedCount`
on gardens) are rewritten in place.

Run order:
    python scripts/migrate_schema.py --project <id> --dry-run
    python scripts/migrate_schema.py --project <id>

Safety:
- Idempotent. Each pass rewrites only fields that still need rewriting;
  a second run is a no-op.
- `--dry-run` prints every intended write/delete but commits nothing.
- Writes happen in two passes per collection:
    1) SET new camelCase fields (merge=True) so readers never see a doc
       mid-rewrite without the new field.
    2) DELETE old snake_case fields with FieldValue.delete().
- Batches of --batch-size writes per commit (default 400).

Caveats:
- User-added plants whose owner is not recoverable get `userId: null`
  (treated as curated). A separate owner-assignment pass may be needed.
- `beds` embedded `id` field is removed; Firestore doc id is authoritative.
"""

from __future__ import annotations

import argparse
import sys
from typing import Any

import firebase_admin
from firebase_admin import credentials, firestore
from google.cloud.firestore_v1 import FieldFilter
from google.cloud.firestore_v1.base_query import FieldFilter as _FF  # noqa: F401

# ---- Field rename tables ---------------------------------------------------

GARDEN_RENAMES = {
    "created_at": "createdAt",
    "updated_at": "updatedAt",
    "user_id": "userId",
    "bed_count": "bedCount",
}

EVENT_RENAMES = {
    "is_completed": "completed",
    "event_type": "eventType",
    "plant_id": "plantId",
    "plant_name": "plantName",
    "bed_id": "bedId",
    "bed_name": "bedName",
    "garden_id": "gardenId",
    "user_id": "userId",
    "created_at": "createdAt",
    "saved_at": "savedAt",
    "completed_at": "completedAt",
}

TASK_RENAMES = {
    "is_completed": "completed",
    "due_date": "dueDate",
    "task_type": "taskType",
    "plant_id": "plantId",
    "plant_name": "plantName",
    "bed_id": "bedId",
    "bed_name": "bedName",
    "garden_id": "gardenId",
    "user_id": "userId",
    "created_at": "createdAt",
    "saved_at": "savedAt",
    "completed_at": "completedAt",
}


class Migrator:
    def __init__(self, db, *, dry_run: bool, batch_size: int) -> None:
        self.db = db
        self.dry_run = dry_run
        self.batch_size = batch_size
        self._pending: list[tuple[str, Any, dict | None]] = []
        self.stats: dict[str, int] = {}

    # ---- low-level batching ------------------------------------------------

    def _queue_set(self, ref, data: dict) -> None:
        self._pending.append(("set", ref, data))
        self._flush_if_full()

    def _queue_delete_fields(self, ref, fields: list[str]) -> None:
        payload = {f: firestore.DELETE_FIELD for f in fields}
        self._pending.append(("delete_fields", ref, payload))
        self._flush_if_full()

    def _queue_delete(self, ref) -> None:
        self._pending.append(("delete", ref, None))
        self._flush_if_full()

    def _flush_if_full(self) -> None:
        if len(self._pending) >= self.batch_size:
            self.flush()

    def flush(self) -> None:
        if not self._pending:
            return
        if self.dry_run:
            for op, ref, data in self._pending:
                print(f"[dry] {op} {ref.path} {data if data else ''}")
            self._pending.clear()
            return
        batch = self.db.batch()
        for op, ref, data in self._pending:
            if op == "set":
                batch.set(ref, data, merge=True)
            elif op == "delete_fields":
                batch.update(ref, data)
            elif op == "delete":
                batch.delete(ref)
        batch.commit()
        self._pending.clear()

    def bump(self, key: str) -> None:
        self.stats[key] = self.stats.get(key, 0) + 1

    # ---- domain passes -----------------------------------------------------

    def migrate_gardens(self) -> None:
        print("== gardens ==")
        for garden in self.db.collection("gardens").stream():
            data = garden.to_dict() or {}
            self._rewrite_doc(garden.reference, data, GARDEN_RENAMES, "garden")
            # bedCount maintenance (if missing or legacy key present).
            camel = {GARDEN_RENAMES.get(k, k): v for k, v in data.items()}
            if "bedCount" not in camel:
                count = sum(1 for _ in garden.reference.collection("beds").stream())
                if self.dry_run:
                    print(f"[dry] set bedCount={count} on {garden.reference.path}")
                else:
                    garden.reference.set({"bedCount": count}, merge=True)
                self.bump("garden_bedcount_set")
            self._migrate_beds(garden.reference)
            garden_user_id = camel.get("userId")
            self._migrate_events(garden.reference, garden_user_id)
            self._migrate_tasks(garden.reference, garden_user_id)
        self.flush()

    def _migrate_beds(self, garden_ref) -> None:
        for bed in garden_ref.collection("beds").stream():
            data = bed.to_dict() or {}
            if "id" in data:
                # Strip stale embedded id; doc id is authoritative.
                if self.dry_run:
                    print(f"[dry] delete field 'id' on {bed.reference.path}")
                else:
                    self._queue_delete_fields(bed.reference, ["id"])
                self.bump("bed_id_stripped")

    def _migrate_events(self, garden_ref, garden_user_id: str | None) -> None:
        for event in garden_ref.collection("events").stream():
            data = event.to_dict() or {}
            self._rewrite_doc(event.reference, data, EVENT_RENAMES, "event")
            camel = {EVENT_RENAMES.get(k, k): v for k, v in data.items()}
            if not camel.get("userId") and garden_user_id:
                self._queue_set(event.reference, {"userId": garden_user_id})
                self.bump("event_userid_stamped")

    def _migrate_tasks(self, garden_ref, garden_user_id: str | None) -> None:
        for task in garden_ref.collection("tasks").stream():
            data = task.to_dict() or {}
            self._rewrite_doc(task.reference, data, TASK_RENAMES, "task")
            camel = {TASK_RENAMES.get(k, k): v for k, v in data.items()}
            if not camel.get("userId") and garden_user_id:
                self._queue_set(task.reference, {"userId": garden_user_id})
                self.bump("task_userid_stamped")

    def migrate_plants(self) -> None:
        print("== plants ==")
        for plant in self.db.collection("plants").stream():
            data = plant.to_dict() or {}
            if "userId" not in data:
                # Treat anything without an explicit owner as curated.
                if self.dry_run:
                    print(f"[dry] set userId=null on {plant.reference.path}")
                else:
                    self._queue_set(plant.reference, {"userId": None})
                self.bump("plant_marked_curated")
        self.flush()

    # ---- generic rewrite helper -------------------------------------------

    def _rewrite_doc(
        self,
        ref,
        data: dict,
        renames: dict[str, str],
        kind: str,
    ) -> None:
        """If any legacy key exists, copy its value to the camelCase key
        (when the camel key is absent) and queue a deletion of the legacy
        key. Safe to re-run: second pass sees no legacy keys."""
        new_fields: dict[str, Any] = {}
        stale_fields: list[str] = []
        for snake, camel in renames.items():
            if snake in data:
                stale_fields.append(snake)
                if camel not in data:
                    new_fields[camel] = data[snake]
        if new_fields:
            self._queue_set(ref, new_fields)
            self.bump(f"{kind}_fields_renamed")
        if stale_fields:
            self._queue_delete_fields(ref, stale_fields)
            self.bump(f"{kind}_legacy_fields_deleted")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True, help="Firebase project id")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--batch-size", type=int, default=400)
    parser.add_argument(
        "--credentials",
        default=None,
        help="Path to service-account JSON. Defaults to GOOGLE_APPLICATION_CREDENTIALS.",
    )
    parser.add_argument(
        "--skip",
        default="",
        help="Comma-separated list of sections to skip: gardens,plants",
    )
    args = parser.parse_args()

    cred = credentials.Certificate(args.credentials) if args.credentials else credentials.ApplicationDefault()
    firebase_admin.initialize_app(cred, {"projectId": args.project})
    db = firestore.client()

    skip = {s.strip() for s in args.skip.split(",") if s.strip()}
    migrator = Migrator(db, dry_run=args.dry_run, batch_size=args.batch_size)
    if "gardens" not in skip:
        migrator.migrate_gardens()
    if "plants" not in skip:
        migrator.migrate_plants()
    migrator.flush()

    print("== summary ==")
    if not migrator.stats:
        print("no changes")
    for k, v in sorted(migrator.stats.items()):
        print(f"{k}: {v}")
    if args.dry_run:
        print("(dry run — no writes committed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
