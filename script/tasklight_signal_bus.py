#!/usr/bin/env python3
"""Shared append-only signal bus helpers for TaskLight signal producers."""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
import tempfile
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_STATE_DIR = Path.home() / ".66tasklight"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def state_dir() -> Path:
    return Path(os.environ.get("TASKLIGHT_STATE_DIR", str(DEFAULT_STATE_DIR))).expanduser()


def signal_bus_path(config_state_dir: Path | None = None) -> Path:
    root = config_state_dir or state_dir()
    return Path(
        os.environ.get("TASKLIGHT_NORMALIZED_SIGNALS_PATH", str(root / "normalized_signals.jsonl"))
    ).expanduser()


def signal_bus_lock_path(config_state_dir: Path | None = None) -> Path:
    root = config_state_dir or state_dir()
    default = signal_bus_path(root).with_suffix(".lock")
    return Path(os.environ.get("TASKLIGHT_SIGNAL_BUS_LOCK_PATH", str(default))).expanduser()


def signal_bus_max_records() -> int:
    return max(10, int(os.environ.get("TASKLIGHT_SIGNAL_BUS_MAX_RECORDS", "5000")))


def signal_bus_retention_seconds() -> float:
    return max(0.0, float(os.environ.get("TASKLIGHT_SIGNAL_BUS_RETENTION_SECONDS", "172800")))


def signal_bus_compact_threshold_bytes() -> int:
    return max(4096, int(os.environ.get("TASKLIGHT_SIGNAL_BUS_MAX_BYTES", str(2 * 1024 * 1024))))


@contextmanager
def signal_bus_lock(config_state_dir: Path | None = None):
    path = signal_bus_lock_path(config_state_dir)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+", encoding="utf-8") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def _stable_signal_id(payload: dict[str, Any]) -> str:
    stable = {
        "source": payload.get("source"),
        "event_type": payload.get("event_type"),
        "task_id": payload.get("task_id"),
        "thread_id": payload.get("thread_id"),
        "turn_id": payload.get("turn_id"),
        "item_id": payload.get("item_id"),
        "cwd": payload.get("cwd"),
        "session_id": payload.get("session_id") or payload.get("sessionId"),
        "observation_id": payload.get("observation_id"),
        "pid": payload.get("pid"),
        "status_hint": payload.get("status_hint"),
        "occurred_at": payload.get("occurred_at"),
        "reason": payload.get("reason"),
        "message": payload.get("message"),
        "raw_event_ref": payload.get("raw_event_ref"),
        "evidence": payload.get("evidence") or [],
        "appserver_activity_evidence": payload.get("appserver_activity_evidence") or [],
        "conflicts": payload.get("conflicts") or [],
    }
    encoded = json.dumps(stable, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    return "sig_" + hashlib.sha256(encoded.encode("utf-8")).hexdigest()[:24]


def canonical_signal(payload: dict[str, Any]) -> dict[str, Any]:
    identity = payload.get("identity") if isinstance(payload.get("identity"), dict) else {}
    task_id = payload.get("task_id") or identity.get("task_id")
    thread_id = payload.get("thread_id") or identity.get("thread_id")
    turn_id = payload.get("turn_id") or identity.get("turn_id")
    item_id = payload.get("item_id") or identity.get("item_id")
    pid = payload.get("pid") or identity.get("pid")
    observation_id = payload.get("observation_id") or identity.get("observation_id")
    cwd = payload.get("cwd") or identity.get("cwd")
    session_id = payload.get("session_id") or payload.get("sessionId")
    occurred_at = payload.get("occurred_at") or payload.get("event_time") or payload.get("checked_at") or now_iso()
    confidence = float(payload.get("confidence") or 0.0)
    signal = {
        "signal_id": payload.get("signal_id")
        or _stable_signal_id(
            {
                **payload,
                "task_id": task_id,
                "thread_id": thread_id,
                "turn_id": turn_id,
                "item_id": item_id,
                "pid": pid,
                "observation_id": observation_id,
                "occurred_at": occurred_at,
            }
        ),
        "source": str(payload.get("source") or "unknown"),
        "event_type": str(payload.get("event_type") or "unknown"),
        "identity": {
            "task_id": task_id,
            "thread_id": thread_id,
            "turn_id": turn_id,
            "item_id": item_id,
            "pid": pid,
            "observation_id": observation_id,
        },
        "task_id": task_id,
        "thread_id": thread_id,
        "turn_id": turn_id,
        "item_id": item_id,
        "pid": pid,
        "observation_id": observation_id,
        "session_id": session_id,
        "cwd": cwd,
        "status_hint": payload.get("status_hint"),
        "occurred_at": occurred_at,
        "confidence": round(confidence, 4),
        "thread_scoped": bool(payload.get("thread_scoped")) if "thread_scoped" in payload else bool(thread_id),
        "turn_scoped": bool(payload.get("turn_scoped")) if "turn_scoped" in payload else bool(turn_id),
        "source_quality": payload.get("source_quality") or "unknown",
        "reason": payload.get("reason"),
        "message": payload.get("message"),
        "evidence": [str(item) for item in (payload.get("evidence") or [])][:12],
        "appserver_activity_evidence": [str(item) for item in (payload.get("appserver_activity_evidence") or [])][:12],
        "conflicts": [str(item) for item in (payload.get("conflicts") or [])][:12],
        "raw_event_ref": payload.get("raw_event_ref"),
        "recorded_at": now_iso(),
    }
    return signal


def _parse_ts(value: Any) -> float | None:
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


def compact_signal_bus(path: Path) -> None:
    if not path.exists():
        return
    try:
        raw_lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return

    cutoff = None
    retention = signal_bus_retention_seconds()
    if retention > 0:
        cutoff = datetime.now(timezone.utc).timestamp() - retention

    kept: list[str] = []
    for raw in raw_lines[-signal_bus_max_records():]:
        if not raw.strip():
            continue
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if not isinstance(payload, dict):
            continue
        if cutoff is not None:
            ts = _parse_ts(payload.get("occurred_at") or payload.get("event_time") or payload.get("recorded_at"))
            if ts is not None and ts < cutoff:
                continue
        kept.append(json.dumps(payload, ensure_ascii=True, sort_keys=True, separators=(",", ":")))

    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        for line in kept:
            handle.write(line + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp_name, path)
    dir_fd = os.open(path.parent, os.O_DIRECTORY)
    try:
        os.fsync(dir_fd)
    finally:
        os.close(dir_fd)


def append_signal(payload: dict[str, Any], config_state_dir: Path | None = None) -> dict[str, Any]:
    signal = canonical_signal(payload)
    path = signal_bus_path(config_state_dir)
    path.parent.mkdir(parents=True, exist_ok=True)
    line = json.dumps(signal, ensure_ascii=True, sort_keys=True, separators=(",", ":")) + "\n"
    with signal_bus_lock(config_state_dir):
        with path.open("a", encoding="utf-8") as handle:
            handle.write(line)
            handle.flush()
            os.fsync(handle.fileno())
        if path.stat().st_size >= signal_bus_compact_threshold_bytes():
            compact_signal_bus(path)
    return signal
