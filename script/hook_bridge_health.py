#!/usr/bin/env python3
"""Read-only, machine-readable health semantics for the Hook Bridge."""

from __future__ import annotations

import argparse
import json
import time
from collections import deque
from datetime import datetime
from pathlib import Path
from typing import Any

from hook_signal_bridge import event_identity, parse_ts


def load_json(path: Path) -> dict[str, Any] | None:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return payload if isinstance(payload, dict) else None


def age_seconds(value: Any, now: float) -> float | None:
    timestamp = parse_ts(value)
    if timestamp is None:
        return None
    return max(0.0, now - timestamp)


def latest_signal(signal_dir: Path) -> tuple[float | None, str | None]:
    latest: tuple[float, str] | None = None
    if not signal_dir.exists():
        return None, None
    for path in sorted(signal_dir.glob("*.jsonl")):
        try:
            with path.open("r", encoding="utf-8") as handle:
                lines = deque(handle, maxlen=200)
            for line in lines:
                payload = json.loads(line)
                if not isinstance(payload, dict):
                    continue
                timestamp = parse_ts(payload.get("event_time") or payload.get("occurred_at"))
                if timestamp is None:
                    continue
                signal_id = event_identity(payload)
                if latest is None or timestamp > latest[0]:
                    latest = (timestamp, signal_id)
        except (OSError, json.JSONDecodeError):
            continue
    return latest if latest else (None, None)


def signal_inventory(signal_dir: Path, offsets: dict[str, Any] | None, processed_ids: set[str]) -> tuple[int, float | None, str | None]:
    pending = 0
    latest_pending: tuple[float, str] | None = None
    if not signal_dir.exists():
        return 0, None, None
    file_offsets = (offsets or {}).get("file_offsets", {})
    if not isinstance(file_offsets, dict):
        file_offsets = {}
    for path in sorted(signal_dir.glob("*.jsonl")):
        try:
            previous = int(file_offsets.get(str(path), 0) or 0)
            with path.open("r", encoding="utf-8") as handle:
                size = path.stat().st_size
                if previous > size:
                    previous = 0
                handle.seek(previous)
                lines = list(handle)
            for line in lines:
                payload = json.loads(line)
                if not isinstance(payload, dict):
                    continue
                signal_id = event_identity(payload)
                if signal_id in processed_ids:
                    continue
                timestamp = parse_ts(payload.get("event_time") or payload.get("occurred_at"))
                if timestamp is None:
                    continue
                pending += 1
                if latest_pending is None or timestamp > latest_pending[0]:
                    latest_pending = (timestamp, signal_id)
        except (OSError, json.JSONDecodeError):
            continue
    return pending, latest_pending[0] if latest_pending else None, latest_pending[1] if latest_pending else None


def summarize(
    *,
    signal_dir: Path,
    offsets_path: Path,
    health_path: Path,
    process_alive: bool,
    launchctl_status: str,
    stale_threshold_sec: float = 15.0,
    idle_threshold_sec: float = 120.0,
    now: float | None = None,
) -> dict[str, Any]:
    current = time.time() if now is None else now
    offsets = load_json(offsets_path)
    health = load_json(health_path)
    latest_input_ts, latest_input_id = latest_signal(signal_dir)
    processed = offsets.get("processed", {}) if offsets else {}
    if not isinstance(processed, dict):
        processed = {}
    processed_ids = set(str(item) for item in (offsets or {}).get("processed_signal_ids", []) if item)
    pending_count, latest_pending_ts, latest_pending_id = signal_inventory(signal_dir, offsets, processed_ids)
    processed_rows = [
        (parse_ts(value.get("seen_at")), str(key))
        for key, value in processed.items()
        if isinstance(value, dict) and parse_ts(value.get("seen_at")) is not None
    ]
    latest_processed_ts, latest_processed_id = max(processed_rows, default=(None, None), key=lambda row: row[0] or 0)
    offset_updated_at = (offsets or {}).get("last_run_at") or (offsets or {}).get("last_seen_at")
    health_written_at = (health or {}).get("updated_at") or (health or {}).get("last_run_at")
    offset_age = age_seconds(offset_updated_at, current)
    health_age = age_seconds(health_written_at, current)
    input_age = None if latest_input_ts is None else max(0.0, current - latest_input_ts)
    processed_age = None if latest_processed_ts is None else max(0.0, current - latest_processed_ts)
    poll_age = offset_age
    health_state = str((health or {}).get("status") or "missing")

    if not process_alive or launchctl_status != "running":
        final_status = "not_running"
        reason = "process_not_alive_or_launchctl_not_running"
    elif offsets is None or health is None:
        final_status = "error"
        reason = "offset_or_health_unreadable"
    elif health_state == "error":
        final_status = "error"
        reason = "bridge_health_reports_error"
    elif pending_count > 0 and (offset_age or float("inf")) > stale_threshold_sec and min(
        processed_age or float("inf"), health_age or float("inf")
    ) > stale_threshold_sec:
        final_status = "stale"
        reason = "pending_input_not_processed_within_threshold"
    elif pending_count > 0:
        final_status = "ok"
        reason = "pending_input_within_processing_threshold"
    elif (health_age or float("inf")) <= stale_threshold_sec:
        final_status = "ok"
        reason = "health_fresh_no_pending_input"
    else:
        # A healthy worker with no pending input is idle, not stale. The old
        # check conflated a quiet worker with a stuck worker.
        final_status = "idle"
        reason = "no_pending_input_worker_idle"

    def field(value: float | None) -> str:
        return "none" if value is None else f"{value:.3f}"

    return {
        "process_alive": "yes" if process_alive else "no",
        "launchctl_status": launchctl_status,
        "latest_input_signal_age_sec": field(input_age),
        "latest_processed_signal_age_sec": field(processed_age),
        "offset_updated_age_sec": field(offset_age),
        "health_written_age_sec": field(health_age),
        "last_processed_signal_id": latest_processed_id or "none",
        "latest_input_signal_id": latest_input_id or "none",
        "latest_pending_signal_id": latest_pending_id or "none",
        "pending_signal_count": str(pending_count),
        "bridge_poll_age_sec": field(poll_age),
        "stale_threshold_sec": f"{stale_threshold_sec:g}",
        "idle_threshold_sec": f"{idle_threshold_sec:g}",
        "health_state": health_state,
        "active_turn_bindings": str((health or {}).get("active_turn_bindings") or 0),
        "final_status": final_status,
        "final_status_reason": reason,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--signal-dir", required=True, type=Path)
    parser.add_argument("--offsets-path", required=True, type=Path)
    parser.add_argument("--health-path", required=True, type=Path)
    parser.add_argument("--process-alive", choices=("yes", "no"), required=True)
    parser.add_argument("--launchctl-status", required=True)
    parser.add_argument("--stale-threshold-sec", type=float, default=15.0)
    parser.add_argument("--idle-threshold-sec", type=float, default=120.0)
    args = parser.parse_args()
    result = summarize(
        signal_dir=args.signal_dir.expanduser(),
        offsets_path=args.offsets_path.expanduser(),
        health_path=args.health_path.expanduser(),
        process_alive=args.process_alive == "yes",
        launchctl_status=args.launchctl_status,
        stale_threshold_sec=args.stale_threshold_sec,
        idle_threshold_sec=args.idle_threshold_sec,
    )
    for key, value in result.items():
        print(f"{key}={value}")
    print(f"STATUS={result['final_status']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
