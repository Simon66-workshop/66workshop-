#!/usr/bin/env python3
"""Background watcher that samples Codex app-server thread/list into the signal bus."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from codex_appserver_bridge import poll_thread_list
from tasklight_signal_bus import append_signal


DEFAULT_STATE_DIR = Path.home() / ".66tasklight"
SCHEMA_VERSION = "0.1"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def state_dir() -> Path:
    return Path(os.environ.get("TASKLIGHT_STATE_DIR", str(DEFAULT_STATE_DIR))).expanduser()


def watcher_state_path(root: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_APPSERVER_THREAD_WATCHER_STATE_PATH", str(root / "appserver_thread_watcher_state.json"))).expanduser()


def watcher_health_path(root: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_APPSERVER_THREAD_WATCHER_HEALTH_PATH", str(root / "appserver_thread_watcher_health.json"))).expanduser()


def parse_ts(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value)
    try:
        return float(text)
    except ValueError:
        pass
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=True, sort_keys=True, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp_name, path)
    dir_fd = os.open(path.parent, os.O_DIRECTORY)
    try:
        os.fsync(dir_fd)
    finally:
        os.close(dir_fd)


def load_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return default


def signal_identity(signal: dict[str, Any]) -> str:
    return str(signal.get("thread_id") or "")


def current_thread_id() -> str | None:
    return os.environ.get("CODEX_THREAD_ID") or None


def active_ttl_seconds() -> float:
    return float(os.environ.get("TASKLIGHT_APPSERVER_THREAD_ACTIVE_TTL_SECONDS", "12"))


def coalesce_seconds() -> float:
    return float(os.environ.get("TASKLIGHT_APPSERVER_THREAD_COALESCE_SECONDS", "2"))


def load_fixture_signals(path: Path) -> list[dict[str, Any]]:
    text = path.read_text(encoding="utf-8")
    stripped = text.strip()
    if not stripped:
        return []
    if stripped.startswith("["):
        payload = json.loads(stripped)
        if not isinstance(payload, list):
            return []
        return [item for item in payload if isinstance(item, dict)]
    records: list[dict[str, Any]] = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        parsed = json.loads(line)
        if isinstance(parsed, dict):
            records.append(parsed)
    return records


def should_emit(signal: dict[str, Any], previous: dict[str, Any] | None, *, now_ts: float) -> bool:
    if previous is None:
        return True
    prev_event = str(previous.get("event_type") or "")
    prev_ts = parse_ts(previous.get("occurred_at"))
    curr_ts = parse_ts(signal.get("event_time") or signal.get("occurred_at"))
    prev_quality = str(previous.get("source_quality") or "")
    curr_quality = str(signal.get("source_quality") or "")
    if str(signal.get("event_type") or "") != prev_event or curr_quality != prev_quality:
        return True
    if prev_ts is None or curr_ts is None:
        return True
    if curr_ts > prev_ts:
        return True
    if now_ts - prev_ts >= coalesce_seconds():
        return True
    return False


def normalize_for_state(signal: dict[str, Any]) -> dict[str, Any]:
    return {
        "thread_id": signal.get("thread_id"),
        "event_type": signal.get("event_type"),
        "source_quality": signal.get("source_quality"),
        "occurred_at": signal.get("event_time") or signal.get("occurred_at"),
        "confidence": signal.get("confidence"),
    }


def is_active_like_signal(signal: dict[str, Any]) -> bool:
    status_hint = str(signal.get("status_hint") or "").lower()
    source_quality = str(signal.get("source_quality") or "").lower()
    evidence = " ".join(str(item) for item in signal.get("appserver_activity_evidence") or [])
    return (
        str(signal.get("event_type") or "") in {"turn_started", "item_started"}
        and status_hint in {"active", "running"}
        and "active" in source_quality
        and bool(evidence)
    )


def promote_recent_activity(signal: dict[str, Any], previous: dict[str, Any] | None, *, now_ts: float) -> dict[str, Any]:
    if previous is None:
        return signal
    status_hint = str(signal.get("status_hint") or "").lower()
    source_quality = str(signal.get("source_quality") or "").lower()
    if status_hint not in {"notloaded", "not_loaded", "unknown"}:
        return signal
    if "thread_list" not in source_quality:
        return signal
    prev_ts = parse_ts(previous.get("occurred_at"))
    curr_ts = parse_ts(signal.get("event_time") or signal.get("occurred_at"))
    if prev_ts is None or curr_ts is None:
        return signal
    if curr_ts <= prev_ts or now_ts - curr_ts > active_ttl_seconds():
        return signal
    promoted = dict(signal)
    promoted["event_type"] = "turn_started"
    promoted["confidence"] = max(float(promoted.get("confidence") or 0.0), 0.78)
    promoted["source_quality"] = "codex_appserver_thread_list_recent_activity"
    promoted["status_hint"] = "active"
    promoted["appserver_activity_evidence"] = ["thread/list:updatedAt advanced"]
    promoted["evidence"] = list(promoted.get("evidence") or []) + ["thread/list:updatedAt advanced"]
    promoted["conflicts"] = []
    return promoted


def write_health(path: Path, *, status: str, emitted_count: int, live_threads: int, diagnostics: list[str], error: str | None) -> None:
    atomic_write_json(
        path,
        {
            "schema_version": SCHEMA_VERSION,
            "status": status,
            "last_run_at": now_iso(),
            "emitted_count": emitted_count,
            "live_threads": live_threads,
            "diagnostics": diagnostics[:8],
            "last_error": error,
            "updated_at": now_iso(),
        },
    )


def run_once(root: Path, timeout: float, limit: int) -> dict[str, Any]:
    state_path = watcher_state_path(root)
    health_path = watcher_health_path(root)
    state = load_json(state_path, {"threads": {}})
    previous_threads = state.get("threads") if isinstance(state, dict) else {}
    if not isinstance(previous_threads, dict):
        previous_threads = {}

    fixture = os.environ.get("TASKLIGHT_APPSERVER_THREAD_WATCHER_FIXTURE")
    if fixture:
        signals = load_fixture_signals(Path(fixture).expanduser())
        diagnostics = ["fixture"]
    else:
        signals, diagnostics = poll_thread_list(timeout, None, limit)
    now_ts = time.time()
    emitted_count = 0
    current = current_thread_id()
    live_threads = 0
    next_threads: dict[str, Any] = {}

    for signal in signals:
        thread_id = signal_identity(signal)
        if not thread_id:
            continue
        previous = previous_threads.get(thread_id) if isinstance(previous_threads.get(thread_id), dict) else None
        signal = promote_recent_activity(signal, previous, now_ts=now_ts)
        if should_emit(signal, previous, now_ts=now_ts):
            append_signal(signal)
            emitted_count += 1
        next_threads[thread_id] = normalize_for_state(signal)
        if current and thread_id == current:
            continue
        signal_ts = parse_ts(signal.get("event_time") or signal.get("occurred_at"))
        if is_active_like_signal(signal) and signal_ts is not None and now_ts - signal_ts <= active_ttl_seconds():
            live_threads += 1

    payload = {
        "schema_version": SCHEMA_VERSION,
        "updated_at": now_iso(),
        "threads": next_threads,
        "last_diagnostics": diagnostics[:8],
    }
    atomic_write_json(state_path, payload)
    write_health(health_path, status="ok", emitted_count=emitted_count, live_threads=live_threads, diagnostics=diagnostics, error=None)
    return {
        "emitted_count": emitted_count,
        "live_threads": live_threads,
        "diagnostics": diagnostics[:8],
        "thread_count": len(next_threads),
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Watch Codex app-server thread/list and emit deduped signal bus records")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--once", action="store_true")
    mode.add_argument("--watch", action="store_true")
    parser.add_argument("--poll-seconds", type=float, default=float(os.environ.get("TASKLIGHT_APPSERVER_THREAD_WATCHER_POLL_SECONDS", "4")))
    parser.add_argument("--timeout", type=float, default=float(os.environ.get("TASKLIGHT_APPSERVER_PROBE_TIMEOUT_SECONDS", "0.6")))
    parser.add_argument("--limit", type=int, default=int(os.environ.get("TASKLIGHT_APPSERVER_THREAD_WATCHER_LIMIT", "25")))
    return parser


def main() -> int:
    args = build_parser().parse_args()
    root = state_dir()
    root.mkdir(parents=True, exist_ok=True)
    health = watcher_health_path(root)
    if args.once:
        try:
            payload = run_once(root, args.timeout, args.limit)
            print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))
            return 0
        except Exception as exc:
            write_health(health, status="error", emitted_count=0, live_threads=0, diagnostics=[], error=str(exc))
            raise

    while True:
        try:
            run_once(root, args.timeout, args.limit)
        except Exception as exc:
            write_health(health, status="error", emitted_count=0, live_threads=0, diagnostics=[], error=str(exc))
        time.sleep(max(1.0, float(args.poll_seconds)))


if __name__ == "__main__":
    raise SystemExit(main())
