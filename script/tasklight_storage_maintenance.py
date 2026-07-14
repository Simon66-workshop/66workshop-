#!/usr/bin/env python3
"""Fail-safe TaskLight storage maintenance. Report-only unless --apply is explicit."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PROTECTED = {"running", "queued", "blocked", "stale", "done_unverified"}
ARCHIVABLE = {"done_verified", "cancelled", "released"}


def parse_timestamp(payload: dict[str, Any], fallback: float) -> float:
    for key in ("updated_at", "done_at", "cancelled_at", "released_at", "created_at"):
        value = payload.get(key)
        if isinstance(value, (int, float)):
            return float(value)
        if value:
            try:
                return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
            except ValueError:
                continue
    return fallback


def plan_directory(source: Path, archive_root: Path, *, keep_recent: int, older_than_days: int, kind: str) -> list[dict[str, Any]]:
    if not source.exists():
        return []
    now = time.time()
    rows: list[tuple[float, Path, dict[str, Any]]] = []
    for path in sorted(source.glob("*.json")):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(payload, dict):
                continue
            stat = path.stat()
        except (OSError, json.JSONDecodeError):
            continue
        status = str(payload.get("status") or payload.get("effective_status") or "unknown")
        timestamp = parse_timestamp(payload, stat.st_mtime)
        if status in PROTECTED or status not in ARCHIVABLE:
            continue
        rows.append((timestamp, path, payload))
    rows.sort(key=lambda item: item[0], reverse=True)
    candidates = rows[keep_recent:]
    cutoff = now - older_than_days * 86400
    plan: list[dict[str, Any]] = []
    for timestamp, path, payload in candidates:
        if timestamp > cutoff:
            continue
        month = datetime.fromtimestamp(timestamp, timezone.utc).strftime("%Y-%m")
        destination = archive_root / kind / month / path.name
        plan.append({
            "source": str(path),
            "destination": str(destination),
            "status": str(payload.get("status") or payload.get("effective_status") or "unknown"),
            "updated_at": datetime.fromtimestamp(timestamp, timezone.utc).isoformat(),
        })
    return plan


def maintenance(state_dir: Path, *, apply: bool, keep_recent: int, older_than_days: int) -> dict[str, Any]:
    archive_root = state_dir / "archive"
    plans = plan_directory(state_dir / "tasks", archive_root, keep_recent=keep_recent, older_than_days=older_than_days, kind="tasks")
    plans += plan_directory(state_dir / "turn_bindings", archive_root, keep_recent=keep_recent, older_than_days=older_than_days, kind="turn_bindings")
    moved = 0
    if apply:
        for item in plans:
            source = Path(item["source"])
            destination = Path(item["destination"])
            if not source.exists():
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(source), str(destination))
            moved += 1
    return {
        "schema_version": "m7.1",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "mode": "apply" if apply else "report_only",
        "planned_count": len(plans),
        "moved_count": moved,
        "protected_statuses": sorted(PROTECTED),
        "archive_root": "<tasklight-state-dir>/archive",
        "plans": plans if apply else [{"status": item["status"], "updated_at": item["updated_at"]} for item in plans],
        "safety": {"active_files_touched": False, "raw_log_output": False, "auth_read": False},
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-dir", default=os.environ.get("TASKLIGHT_STATE_DIR", str(Path.home() / ".66tasklight")))
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--report-only", action="store_true")
    parser.add_argument("--keep-recent", type=int, default=2000)
    parser.add_argument("--older-than-days", type=int, default=30)
    parser.add_argument("--output-json")
    args = parser.parse_args()
    if args.apply and (args.dry_run or args.report_only):
        parser.error("--apply cannot be combined with --dry-run or --report-only")
    payload = maintenance(Path(args.state_dir).expanduser(), apply=args.apply, keep_recent=max(0, args.keep_recent), older_than_days=max(1, args.older_than_days))
    encoded = json.dumps(payload, ensure_ascii=True, indent=2) + "\n"
    if args.output_json:
        Path(args.output_json).write_text(encoded, encoding="utf-8")
    print(f"storage_maintenance_mode={payload['mode']} planned_count={payload['planned_count']} moved_count={payload['moved_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
