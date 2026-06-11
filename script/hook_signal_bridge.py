#!/usr/bin/env python3
"""Bridge trusted Codex hook signals into tasklight managed tasks."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from contextlib import contextmanager


SCHEMA_VERSION = "0.1"
PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_STATE_DIR = Path.home() / ".66tasklight"
TERMINAL_STATUSES = {"blocked", "done_unverified", "done_verified", "cancelled"}
ACTIVE_STATUSES = {"running", "queued", "stale"}
REACTIVATABLE_RELEASE_REASONS = {"completed_idle_timeout", "lease_timeout"}
REACTIVATING_EVENTS = {"turn_started", "item_started"}
ACTIVE_EVENTS = {"turn_started", "item_started", "item_completed"}
BLOCK_EVENTS = {"approval_pending", "tool_failed"}
DONE_EVENTS = {"stop"}
MANAGED_EVENTS = ACTIVE_EVENTS | BLOCK_EVENTS | DONE_EVENTS


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


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


def load_json(path: Path, default: dict[str, Any]) -> dict[str, Any]:
    if not path.exists():
        return default.copy()
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return default.copy()
    return payload if isinstance(payload, dict) else default.copy()


def state_dir() -> Path:
    return Path(os.environ.get("TASKLIGHT_STATE_DIR", str(DEFAULT_STATE_DIR))).expanduser()


def signal_dir(config_state_dir: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_SIGNAL_SPOOL_DIR", str(config_state_dir / "signals"))).expanduser()


def turn_bindings_dir(config_state_dir: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_TURN_BINDINGS_DIR", str(config_state_dir / "turn_bindings"))).expanduser()


def offsets_path(config_state_dir: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_HOOK_BRIDGE_OFFSETS_PATH", str(config_state_dir / "hook_bridge_offsets.json"))).expanduser()


def health_path(config_state_dir: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH", str(config_state_dir / "hook_bridge_health.json"))).expanduser()


def lock_path(config_state_dir: Path) -> Path:
    return config_state_dir / "hook_bridge.lock"


@contextmanager
def bridge_lock(config_state_dir: Path):
    path = lock_path(config_state_dir)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+", encoding="utf-8") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def tasklight_bin() -> str:
    return os.environ.get("TASKLIGHT_BIN", str(PROJECT_ROOT / "tasklight"))


def safe_file_stem(source_key: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "_", source_key).strip("._")
    digest = hashlib.sha256(source_key.encode("utf-8")).hexdigest()[:10]
    if len(cleaned) > 90:
        cleaned = cleaned[:90].rstrip("._-")
    return f"{cleaned}-{digest}"


def event_identity(signal: dict[str, Any]) -> str:
    stable = {
        "source": signal.get("source"),
        "event_type": signal.get("event_type"),
        "thread_id": signal.get("thread_id"),
        "turn_id": signal.get("turn_id"),
        "item_id": signal.get("item_id"),
        "event_time": signal.get("event_time"),
        "raw_event_ref": signal.get("raw_event_ref"),
        "reason": signal.get("reason"),
        "message": signal.get("message"),
    }
    encoded = json.dumps(stable, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def subprocess_json(args: list[str], timeout: float = 10.0) -> dict[str, Any]:
    completed = subprocess.run(
        args,
        cwd=str(PROJECT_ROOT),
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or f"{args[0]} exited {completed.returncode}")
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"invalid JSON from {' '.join(args[:2])}: {exc}") from exc
    if not isinstance(payload, dict):
        raise RuntimeError("expected JSON object from tasklight")
    return payload


def task_status(task_id: str) -> str | None:
    try:
        payload = subprocess_json([tasklight_bin(), "show", task_id], timeout=5)
    except Exception:
        return None
    return str(payload.get("status") or "")


def start_task(title: str) -> str:
    payload = subprocess_json([tasklight_bin(), "start", "--title", title], timeout=10)
    task_id = payload.get("task_id")
    if not task_id:
        raise RuntimeError("tasklight start did not return task_id")
    return str(task_id)


def heartbeat(task_id: str, phase: str, progress: float) -> None:
    subprocess_json(
        [tasklight_bin(), "heartbeat", "--task-id", task_id, "--phase", phase, "--progress", str(progress)],
        timeout=10,
    )


def block(task_id: str, reason: str, message: str, evidence: str) -> None:
    subprocess_json(
        [tasklight_bin(), "block", "--task-id", task_id, "--reason", reason, "--message", message, "--evidence", evidence],
        timeout=10,
    )


def done(task_id: str, summary: str) -> None:
    subprocess_json([tasklight_bin(), "done", "--task-id", task_id, "--summary", summary], timeout=10)


def release(task_id: str) -> None:
    subprocess_json([tasklight_bin(), "release", "--task-id", task_id], timeout=10)


def signal_session_id(signal: dict[str, Any]) -> str | None:
    value = signal.get("session_id") or signal.get("sessionId")
    return str(value) if value else None


def source_key_for(signal: dict[str, Any]) -> str:
    session_id = signal_session_id(signal) or "unknown"
    return f"hook:{session_id}:{signal['turn_id']}"


def binding_path_for(bindings_dir: Path, source_key: str) -> Path:
    return bindings_dir / f"{safe_file_stem(source_key)}.json"


def find_binding(bindings_dir: Path, turn_id: str) -> tuple[Path, dict[str, Any]] | None:
    if not bindings_dir.exists():
        return None
    for path in sorted(bindings_dir.glob("*.json")):
        payload = load_json(path, {})
        if payload.get("turn_id") == turn_id:
            return path, payload
    return None


def new_binding(signal: dict[str, Any], bindings_dir: Path) -> tuple[Path, dict[str, Any]]:
    source_key = source_key_for(signal)
    title = f"Codex turn {str(signal['turn_id'])[:8]}"
    task_id = start_task(title)
    timestamp = now_iso()
    aliases: list[str] = []
    thread_id = signal.get("thread_id")
    if thread_id:
        aliases.append(f"appserver:{thread_id}:{signal['turn_id']}")
    binding = {
        "schema_version": SCHEMA_VERSION,
        "source_key": source_key,
        "aliases": aliases,
        "task_id": task_id,
        "thread_id": thread_id,
        "turn_id": signal.get("turn_id"),
        "session_id": signal_session_id(signal),
        "title": title,
        "cwd": str(PROJECT_ROOT),
        "status": "active",
        "created_at": timestamp,
        "updated_at": timestamp,
        "last_signal_at": timestamp,
        "last_signal_event": None,
        "phase": "turn_started",
        "signal_count": 0,
        "released_at": None,
    }
    path = binding_path_for(bindings_dir, source_key)
    atomic_write_json(path, binding)
    return path, binding


def replace_released_task(binding: dict[str, Any], signal: dict[str, Any]) -> str:
    previous_task_ids = list(binding.get("previous_task_ids") or [])
    previous_task_id = str(binding.get("task_id") or "")
    if previous_task_id and previous_task_id not in previous_task_ids:
        previous_task_ids.append(previous_task_id)
    title = str(binding.get("title") or f"Codex turn {str(signal['turn_id'])[:8]}")
    task_id = start_task(title)
    timestamp = now_iso()
    binding["task_id"] = task_id
    binding["status"] = "active"
    binding["previous_task_ids"] = previous_task_ids[-20:]
    binding["reactivated_at"] = timestamp
    binding["reactivation_count"] = int(binding.get("reactivation_count") or 0) + 1
    binding["released_at"] = None
    binding.pop("release_reason", None)
    return task_id


def get_or_create_binding(signal: dict[str, Any], bindings_dir: Path) -> tuple[Path, dict[str, Any]]:
    found = find_binding(bindings_dir, str(signal["turn_id"]))
    if found:
        return found
    return new_binding(signal, bindings_dir)


def sanitized_evidence(signal: dict[str, Any]) -> str:
    safe = {
        "source": signal.get("source"),
        "event_type": signal.get("event_type"),
        "turn_id": signal.get("turn_id"),
        "item_id": signal.get("item_id"),
        "event_time": signal.get("event_time"),
        "raw_event_ref": signal.get("raw_event_ref"),
    }
    return " ".join(f"{key}={value}" for key, value in safe.items() if value not in (None, ""))


def event_phase(event_type: str) -> str:
    if event_type == "turn_started":
        return "turn_started"
    if event_type == "item_started":
        return "tool_running"
    if event_type == "item_completed":
        return "item_completed"
    if event_type == "approval_pending":
        return "needs_human_review"
    if event_type == "tool_failed":
        return "tool_failed"
    if event_type == "stop":
        return "done_unverified"
    return "hook_signal"


def progress_for(event_type: str) -> float:
    if event_type == "turn_started":
        return 0.10
    if event_type == "item_started":
        return 0.45
    if event_type == "item_completed":
        return 0.70
    return 0.20


def coalesce_key(turn_id: str, phase: str) -> str:
    raw = f"{turn_id}:{phase}"
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]
    return f"{turn_id}:{phase}:{digest}"


def should_write_heartbeat(
    offsets: dict[str, Any],
    task_id: str,
    turn_id: str,
    phase: str,
    progress: float,
    window_seconds: float,
) -> bool:
    if window_seconds <= 0:
        return True
    ledger = offsets.setdefault("heartbeat_coalesce", {})
    key = coalesce_key(turn_id, phase)
    previous = ledger.get(key)
    if not isinstance(previous, dict):
        return True
    previous_ts = parse_ts(previous.get("written_at"))
    if previous_ts is None:
        return True
    if previous.get("task_id") != task_id:
        return True
    if previous.get("phase") != phase:
        return True
    try:
        previous_progress = float(previous.get("progress"))
    except (TypeError, ValueError):
        return True
    if abs(previous_progress - progress) > 0.000001:
        return True
    return time.time() - previous_ts >= window_seconds


def record_heartbeat_write(
    offsets: dict[str, Any],
    task_id: str,
    turn_id: str,
    phase: str,
    progress: float,
    decision: str,
) -> None:
    ledger = offsets.setdefault("heartbeat_coalesce", {})
    key = coalesce_key(turn_id, phase)
    ledger[key] = {
        "task_id": task_id,
        "turn_id": turn_id,
        "phase": phase,
        "progress": progress,
        "decision": decision,
        "written_at": now_iso(),
    }
    if len(ledger) > 500:
        for stale_key in list(ledger.keys())[:-500]:
            ledger.pop(stale_key, None)


def update_stop_diagnostics(offsets: dict[str, Any], decision: str, *, late_recovered: bool = False) -> None:
    diagnostics = offsets.setdefault("stop_diagnostics", {})
    diagnostics["latest_stop_decision"] = decision
    diagnostics["latest_stop_seen_at"] = now_iso()
    if late_recovered:
        diagnostics["late_stop_recovered_count"] = int(diagnostics.get("late_stop_recovered_count") or 0) + 1
    if decision.startswith("stop_ignored"):
        diagnostics["stop_ignored_count"] = int(diagnostics.get("stop_ignored_count") or 0) + 1
    diagnostics["stop_seen_count"] = int(diagnostics.get("stop_seen_count") or 0) + 1


def update_release_diagnostics(offsets: dict[str, Any], release_reason: str) -> None:
    diagnostics = offsets.setdefault("stop_diagnostics", {})
    if release_reason in REACTIVATABLE_RELEASE_REASONS:
        diagnostics["soft_release_count"] = int(diagnostics.get("soft_release_count") or 0) + 1
    diagnostics["latest_release_reason"] = release_reason
    diagnostics["latest_release_seen_at"] = now_iso()


def count_active_bindings(bindings_dir: Path) -> int:
    if not bindings_dir.exists():
        return 0
    active = 0
    for path in bindings_dir.glob("*.json"):
        payload = load_json(path, {})
        if payload.get("status") == "active":
            active += 1
    return active


def health_payload(
    *,
    status: str,
    offsets: dict[str, Any] | None,
    processed_count: int,
    expired_count: int,
    superseded_count: int,
    active_turn_bindings: int,
    last_error: str | None,
) -> dict[str, Any]:
    timestamp = now_iso()
    stop_diagnostics = (offsets or {}).get("stop_diagnostics") if isinstance(offsets, dict) else {}
    if not isinstance(stop_diagnostics, dict):
        stop_diagnostics = {}
    return {
        "schema_version": SCHEMA_VERSION,
        "status": status,
        "last_run_at": timestamp,
        "last_seen_at": (offsets or {}).get("last_seen_at"),
        "processed_count": processed_count,
        "expired_count": expired_count,
        "superseded_count": superseded_count,
        "active_turn_bindings": active_turn_bindings,
        "latest_stop_decision": stop_diagnostics.get("latest_stop_decision"),
        "latest_stop_seen_at": stop_diagnostics.get("latest_stop_seen_at"),
        "late_stop_recovered_count": int(stop_diagnostics.get("late_stop_recovered_count") or 0),
        "soft_release_count": int(stop_diagnostics.get("soft_release_count") or 0),
        "stop_ignored_count": int(stop_diagnostics.get("stop_ignored_count") or 0),
        "last_error": last_error,
        "updated_at": timestamp,
    }


def write_health(path: Path, payload: dict[str, Any]) -> None:
    atomic_write_json(path, payload)


def apply_signal(signal: dict[str, Any], bindings_dir: Path, offsets: dict[str, Any], coalesce_seconds: float) -> dict[str, Any]:
    if signal.get("source") != "codex_hook":
        return {"decision": "ignored_non_hook"}
    if not signal.get("turn_id"):
        return {"decision": "ignored_missing_turn_id"}

    event_type = str(signal.get("event_type") or "unknown")
    if event_type not in MANAGED_EVENTS:
        return {"decision": "ignored_unknown"}

    path, binding = get_or_create_binding(signal, bindings_dir)
    task_id = str(binding["task_id"])
    turn_id = str(signal["turn_id"])
    current_status = task_status(task_id)
    timestamp = now_iso()
    phase = event_phase(event_type)
    decision = "ignored_unknown"

    if (
        binding.get("status") == "released"
        and event_type in REACTIVATING_EVENTS
        and current_status == "cancelled"
        and binding.get("release_reason") in REACTIVATABLE_RELEASE_REASONS
    ):
        task_id = replace_released_task(binding, signal)
        current_status = task_status(task_id)
        decision = "reactivated_released_turn"

    thread_id = signal.get("thread_id")
    if thread_id and not binding.get("thread_id"):
        binding["thread_id"] = thread_id
    if thread_id:
        alias = f"appserver:{thread_id}:{signal['turn_id']}"
        aliases = list(binding.get("aliases") or [])
        if alias not in aliases:
            aliases.append(alias)
        binding["aliases"] = aliases

    if current_status in TERMINAL_STATUSES:
        if event_type == "stop":
            allow_late_stop = bool(binding.get("allow_late_stop")) or binding.get("release_kind") == "soft_timeout" or binding.get("release_reason") in REACTIVATABLE_RELEASE_REASONS
            if current_status == "done_verified":
                decision = "stop_ignored_already_verified"
            elif current_status == "done_unverified":
                decision = "stop_idempotent_done_unverified"
            elif current_status == "blocked":
                decision = "stop_after_blocked_diagnostic"
            elif current_status == "cancelled" and allow_late_stop:
                done(task_id, "Codex turn stopped; awaiting verify")
                decision = "stop_to_done_unverified"
                update_stop_diagnostics(offsets, decision, late_recovered=True)
            elif current_status == "cancelled":
                decision = "stop_ignored_user_cancelled"
            else:
                decision = f"stop_ignored_terminal_{current_status}"
            if decision != "stop_to_done_unverified":
                update_stop_diagnostics(offsets, decision)
        else:
            decision = f"ignored_terminal_{current_status}"
    elif event_type in ACTIVE_EVENTS:
        progress = progress_for(event_type)
        if should_write_heartbeat(offsets, task_id, turn_id, phase, progress, coalesce_seconds):
            heartbeat(task_id, phase, progress)
            record_heartbeat_write(offsets, task_id, turn_id, phase, progress, "heartbeat")
            decision = "heartbeat"
        else:
            decision = "heartbeat_coalesced"
    elif event_type == "approval_pending":
        block(task_id, "needs_human_review", "Codex is waiting for approval", sanitized_evidence(signal))
        decision = "blocked_needs_human_review"
    elif event_type == "tool_failed":
        block(task_id, "codex_exit_failed", "Codex tool execution failed", sanitized_evidence(signal))
        decision = "blocked_codex_exit_failed"
    elif event_type == "stop":
        done(task_id, "Codex turn stopped; awaiting verify")
        decision = "stop_to_done_unverified"
        update_stop_diagnostics(offsets, decision)

    binding["status"] = "released" if decision.startswith("stop_") else binding.get("status", "active")
    binding["phase"] = phase
    binding["updated_at"] = timestamp
    binding["last_signal_at"] = timestamp
    binding["last_signal_event"] = event_type
    binding["last_bridge_decision"] = decision
    binding["signal_count"] = int(binding.get("signal_count") or 0) + 1
    if binding["status"] == "released":
        binding["released_at"] = binding.get("released_at") or timestamp
        if decision.startswith("stop_"):
            binding["release_kind"] = binding.get("release_kind") or "stop"
            binding["released_by"] = "stop"
            binding["allow_late_stop"] = False
    atomic_write_json(path, binding)
    return {"decision": decision, "task_id": task_id, "binding": str(path)}


def offsets_default() -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "file_offsets": {},
        "processed_signal_ids": [],
        "processed": {},
        "heartbeat_coalesce": {},
        "diagnostics": [],
        "last_seen_at": None,
    }


def read_new_signals(signals_dir: Path, offsets: dict[str, Any], max_age_seconds: float) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    signals: list[dict[str, Any]] = []
    file_offsets = offsets.setdefault("file_offsets", {})
    processed_ids = set(offsets.get("processed_signal_ids") or [])
    processed = offsets.setdefault("processed", {})
    diagnostics = offsets.setdefault("diagnostics", [])
    cutoff = time.time() - max_age_seconds

    if not signals_dir.exists():
        return signals, offsets

    for path in sorted(signals_dir.glob("*.jsonl")):
        previous = int(file_offsets.get(str(path), 0) or 0)
        try:
            size = path.stat().st_size
        except OSError:
            continue
        if previous > size:
            previous = 0
        with path.open("r", encoding="utf-8") as handle:
            handle.seek(previous)
            for line in handle:
                raw = line.strip()
                if not raw:
                    continue
                try:
                    signal = json.loads(raw)
                except json.JSONDecodeError:
                    diagnostics.append({"path": str(path), "decision": "invalid_json", "seen_at": now_iso()})
                    continue
                if not isinstance(signal, dict):
                    continue
                signal_id = event_identity(signal)
                if signal_id in processed_ids:
                    processed[signal_id] = {"decision": "duplicate", "seen_at": now_iso()}
                    continue
                event_ts = parse_ts(signal.get("event_time"))
                if event_ts is not None and event_ts < cutoff:
                    processed_ids.add(signal_id)
                    processed[signal_id] = {"decision": "ignored_old_signal", "seen_at": now_iso()}
                    continue
                processed_ids.add(signal_id)
                signal["_bridge_signal_id"] = signal_id
                signals.append(signal)
            file_offsets[str(path)] = handle.tell()

    offsets["processed_signal_ids"] = list(processed_ids)[-2000:]
    offsets["diagnostics"] = diagnostics[-50:]
    return signals, offsets


def mark_processed(offsets: dict[str, Any], signal: dict[str, Any], result: dict[str, Any]) -> None:
    signal_id = signal.get("_bridge_signal_id") or event_identity(signal)
    processed_ids = list(offsets.get("processed_signal_ids") or [])
    if signal_id not in processed_ids:
        processed_ids.append(str(signal_id))
    offsets["processed_signal_ids"] = processed_ids[-2000:]
    processed = offsets.setdefault("processed", {})
    processed[str(signal_id)] = {
        "decision": result.get("decision"),
        "task_id": result.get("task_id"),
        "turn_id": signal.get("turn_id"),
        "event_type": signal.get("event_type"),
        "seen_at": now_iso(),
    }
    if len(processed) > 2000:
        for key in list(processed.keys())[:-2000]:
            processed.pop(key, None)
    offsets["last_seen_at"] = now_iso()


def binding_release_after_seconds(binding: dict[str, Any], lease_seconds: float, completed_idle_seconds: float) -> float:
    if binding.get("last_signal_event") == "item_completed" and completed_idle_seconds > 0:
        return min(lease_seconds, completed_idle_seconds)
    return lease_seconds


def expire_bindings(bindings_dir: Path, lease_seconds: float, completed_idle_seconds: float, offsets: dict[str, Any]) -> list[dict[str, Any]]:
    expired: list[dict[str, Any]] = []
    if not bindings_dir.exists():
        return expired
    now_ts = time.time()
    for path in sorted(bindings_dir.glob("*.json")):
        binding = load_json(path, {})
        if binding.get("status") != "active":
            continue
        last_ts = parse_ts(binding.get("last_signal_at") or binding.get("updated_at") or binding.get("created_at"))
        release_after = binding_release_after_seconds(binding, lease_seconds, completed_idle_seconds)
        if last_ts is None or now_ts - last_ts <= release_after:
            continue
        task_id = str(binding.get("task_id") or "")
        status = task_status(task_id) if task_id else None
        timestamp = now_iso()
        release_reason = "completed_idle_timeout" if binding.get("last_signal_event") == "item_completed" else "lease_timeout"
        if task_id and status in ACTIVE_STATUSES:
            release(task_id)
            expired.append({"task_id": task_id, "decision": "released", "release_reason": release_reason})
        else:
            expired.append({"task_id": task_id, "decision": f"binding_released_task_{status}", "release_reason": release_reason})
        binding["status"] = "released"
        binding["released_at"] = binding.get("released_at") or timestamp
        binding["release_reason"] = release_reason
        binding["release_kind"] = "soft_timeout"
        binding["released_by"] = release_reason
        binding["allow_late_stop"] = True
        binding["updated_at"] = timestamp
        update_release_diagnostics(offsets, release_reason)
        atomic_write_json(path, binding)
    return expired


def release_superseded_released_tasks(bindings_dir: Path) -> list[dict[str, Any]]:
    """Release old hook-projected pending/stale tasks once a newer turn is active."""
    if not bindings_dir.exists():
        return []

    bindings: list[tuple[Path, dict[str, Any]]] = []
    for path in sorted(bindings_dir.glob("*.json")):
        binding = load_json(path, {})
        if binding.get("task_id"):
            bindings.append((path, binding))

    active_task_ids: set[str] = set()
    for _, binding in bindings:
        if binding.get("status") != "active":
            continue
        task_id = str(binding.get("task_id") or "")
        status = task_status(task_id) if task_id else None
        if status in ACTIVE_STATUSES:
            active_task_ids.add(task_id)

    if not active_task_ids:
        return []

    released: list[dict[str, Any]] = []
    timestamp = now_iso()
    for path, binding in bindings:
        if binding.get("status") != "released":
            continue
        task_id = str(binding.get("task_id") or "")
        if not task_id or task_id in active_task_ids:
            continue
        status = task_status(task_id)
        if status != "stale":
            continue
        release(task_id)
        binding["status"] = "released"
        binding["updated_at"] = timestamp
        binding["released_at"] = binding.get("released_at") or timestamp
        binding["superseded_at"] = timestamp
        binding["superseded_by_task_ids"] = sorted(active_task_ids)
        atomic_write_json(path, binding)
        released.append({"task_id": task_id, "decision": "released_superseded", "previous_status": status})
    return released


def bridge_once(args: argparse.Namespace) -> dict[str, Any]:
    config_state_dir = state_dir()
    with bridge_lock(config_state_dir):
        return bridge_once_unlocked(args, config_state_dir)


def bridge_once_unlocked(args: argparse.Namespace, config_state_dir: Path) -> dict[str, Any]:
    signals_dir = Path(args.signal_dir).expanduser() if args.signal_dir else signal_dir(config_state_dir)
    bindings_dir = Path(args.turn_bindings_dir).expanduser() if args.turn_bindings_dir else turn_bindings_dir(config_state_dir)
    offsets_file = Path(args.offsets_path).expanduser() if args.offsets_path else offsets_path(config_state_dir)
    health_file = Path(args.health_path).expanduser() if args.health_path else health_path(config_state_dir)
    lease_seconds = float(args.lease_seconds)
    completed_idle_seconds = float(args.completed_idle_release_seconds)
    max_age_seconds = float(args.max_signal_age_seconds)
    coalesce_seconds = float(args.coalesce_seconds)

    offsets = load_json(offsets_file, offsets_default())
    new_signals, offsets = read_new_signals(signals_dir, offsets, max_age_seconds=max_age_seconds)
    results: list[dict[str, Any]] = []
    for signal in new_signals:
        result = apply_signal(signal, bindings_dir, offsets, coalesce_seconds=coalesce_seconds)
        mark_processed(offsets, signal, result)
        results.append(result)
    expired = expire_bindings(bindings_dir, lease_seconds=lease_seconds, completed_idle_seconds=completed_idle_seconds, offsets=offsets)
    superseded = release_superseded_released_tasks(bindings_dir)
    offsets["last_run_at"] = now_iso()
    atomic_write_json(offsets_file, offsets)
    active_turn_bindings = count_active_bindings(bindings_dir)
    write_health(
        health_file,
        health_payload(
            status="ok",
            offsets=offsets,
            processed_count=len(new_signals),
            expired_count=len(expired),
            superseded_count=len(superseded),
            active_turn_bindings=active_turn_bindings,
            last_error=None,
        ),
    )
    return {
        "signals_dir": str(signals_dir),
        "turn_bindings_dir": str(bindings_dir),
        "offsets_path": str(offsets_file),
        "health_path": str(health_file),
        "coalesce_seconds": coalesce_seconds,
        "completed_idle_release_seconds": completed_idle_seconds,
        "processed_count": len(new_signals),
        "results": results,
        "expired": expired,
        "superseded": superseded,
        "active_turn_bindings": active_turn_bindings,
        "status": "ok",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Bridge Codex hook signals into tasklight managed tasks")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--once", action="store_true")
    mode.add_argument("--watch", action="store_true")
    parser.add_argument("--signal-dir")
    parser.add_argument("--turn-bindings-dir")
    parser.add_argument("--offsets-path")
    parser.add_argument("--health-path")
    parser.add_argument("--lease-seconds", type=float, default=float(os.environ.get("TASKLIGHT_HOOK_TURN_LEASE_SECONDS", "60")))
    parser.add_argument("--completed-idle-release-seconds", type=float, default=float(os.environ.get("TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS", "6")))
    parser.add_argument("--poll-seconds", type=float, default=float(os.environ.get("TASKLIGHT_HOOK_BRIDGE_POLL_SECONDS", "1")))
    parser.add_argument("--max-signal-age-seconds", type=float, default=float(os.environ.get("TASKLIGHT_HOOK_SIGNAL_MAX_AGE_SECONDS", "600")))
    parser.add_argument("--coalesce-seconds", type=float, default=float(os.environ.get("TASKLIGHT_HOOK_BRIDGE_COALESCE_SECONDS", "2")))
    args = parser.parse_args()

    if args.once:
        print(json.dumps(bridge_once(args), ensure_ascii=True, sort_keys=True, indent=2))
        return 0

    while True:
        try:
            bridge_once(args)
        except Exception as exc:
            config_state_dir = state_dir()
            bindings_dir = Path(args.turn_bindings_dir).expanduser() if args.turn_bindings_dir else turn_bindings_dir(config_state_dir)
            offsets_file = Path(args.offsets_path).expanduser() if args.offsets_path else offsets_path(config_state_dir)
            health_file = Path(args.health_path).expanduser() if args.health_path else health_path(config_state_dir)
            offsets = load_json(offsets_file, offsets_default())
            write_health(
                health_file,
                health_payload(
                    status="error",
                    offsets=offsets,
                    processed_count=0,
                    expired_count=0,
                    superseded_count=0,
                    active_turn_bindings=count_active_bindings(bindings_dir),
                    last_error=str(exc),
                ),
            )
        time.sleep(args.poll_seconds)


if __name__ == "__main__":
    raise SystemExit(main())
