#!/usr/bin/env python3
"""Project local 66TaskLight inputs into the LuckyCat UI read model.

The projector is intentionally read-mostly: it reads task, hook, observation,
and diagnostic sidecars, then atomically writes ui_state.json. It does not call
tasklight writer commands and does not change task protocol semantics.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "0.1"
PROJECTOR_VERSION = "M3.7"
DEFAULT_STATE_DIR = Path.home() / ".66tasklight"
PROJECT_ROOT = Path(__file__).resolve().parents[1]
PROJECTOR_INSTANCE_ID = f"{int(time.time())}-{os.getpid()}"
PROJECTOR_LAUNCH_LABEL = os.environ.get("TASKLIGHT_STATE_PROJECTOR_LABEL", "com.66tasklight.state-projector")
DISPLAY_SCOPES = {
    "active_execution",
    "observed_active_high_confidence",
    "observed_only",
    "ignored",
    "open_blocker",
    "stale_blocker",
    "resolved_blocker",
    "pending_verify",
    "recent_done",
    "history",
    "released",
    "invalid",
}
ACTIVE_SIGNAL_EVENTS = {
    "task_started",
    "heartbeat",
    "turn_started",
    "item_started",
    "item_completed",
    "private_active",
    "bridge_running",
}
BLOCK_SIGNAL_EVENTS = {
    "blocked",
    "approval_pending",
    "tool_failed",
    "command_failed",
    "error",
    "bridge_blocked",
    "bridge_stop_after_blocked",
}
DONE_SIGNAL_EVENTS = {"turn_completed", "stop", "bridge_done_unverified"}
VERIFIED_SIGNAL_EVENTS = {"verified"}
RELEASE_SIGNAL_EVENTS = {"release", "bridge_soft_released"}
OBSERVED_EXCLUDE_SNIPPETS = (
    "hook_signal_bridge.py",
    "tasklight.py observe-local",
    "codex app-server",
    "app-server --listen",
    "node_repl",
    "chronicle/screen_recording",
    "screen_recording",
    "computer use.app",
    "skycomputeruse",
    "hermes gateway",
    "gateway run --replace",
    "memory server",
)


def load_params_file(name: str) -> dict[str, Any]:
    path = PROJECT_ROOT / "design" / "state-projector" / "params" / name
    payload = load_json(path, {})
    return payload if isinstance(payload, dict) else {}


def runtime_confidence_config() -> dict[str, Any]:
    payload = load_params_file("runtime_confidence.json")
    return payload if payload else {
        "base_confidence": {
            "explicit_tasklight": 1.0,
            "wrapper_managed_task": 0.98,
            "codex_hook_turn": 0.95,
            "codex_appserver_active": 0.95,
            "private_probe_turn_scoped": 0.8,
            "private_probe_thread_scoped": 0.7,
            "private_probe_global_only": 0.3,
            "process_observer": 0.35,
            "current_thread_watcher": 0.7,
        },
        "identity_score": {"turn_id": 1.0, "thread_id": 0.8, "pid_cwd_only": 0.4, "global_only": 0.2},
        "consistency_score": {
            "hook_and_appserver_agree": 1.0,
            "one_strong_source_fresh": 0.9,
            "appserver_idle_hook_stale": 0.3,
            "process_only_max": 0.6,
            "private_global_only_max": 0.3,
        },
        "scope_thresholds": {"active_execution_min": 0.85, "observed_active_high_confidence_min": 0.55, "observed_only_min": 0.35},
    }


def runtime_ttl_config() -> dict[str, float]:
    payload = load_params_file("runtime_ttl.json")
    ttl = payload.get("ttl_seconds") if isinstance(payload.get("ttl_seconds"), dict) else {}
    return {
        "codex_hook": float(os.environ.get("TASKLIGHT_HOOK_ACTIVE_DISPLAY_TTL_SECONDS", ttl.get("codex_hook_active", 12))),
        "codex_appserver": float(os.environ.get("TASKLIGHT_APPSERVER_THREAD_ACTIVE_TTL_SECONDS", ttl.get("codex_appserver_active", 10))),
        "codex_private_probe": float(os.environ.get("TASKLIGHT_PRIVATE_PROBE_ACTIVE_TTL_SECONDS", ttl.get("private_probe_active", 6))),
        "process_observer": float(os.environ.get("TASKLIGHT_OBSERVED_ACTIVE_TTL_SECONDS", ttl.get("process_observer", 5))),
        "current_thread_watcher": float(os.environ.get("TASKLIGHT_CURRENT_THREAD_ACTIVE_DISPLAY_TTL_SECONDS", ttl.get("current_thread_watcher", 8))),
    }


def verification_ttl_seconds() -> float:
    return max(0.0, float(os.environ.get("TASKLIGHT_VERIFICATION_TTL_SECONDS", "900")))


def projector_code_hash() -> str:
    try:
        digest = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    except OSError:
        digest = "unreadable"
    return f"sha256:{digest}"


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


def age_seconds(value: Any, now_ts: float) -> float | None:
    ts = parse_ts(value)
    if ts is None:
        return None
    return max(0.0, now_ts - ts)


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
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return default
    return payload


def write_jsonl(path: Path, records: list[dict[str, Any]], limit: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bounded = records[-limit:]
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        for record in bounded:
            handle.write(json.dumps(record, ensure_ascii=True, sort_keys=True, separators=(",", ":")) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp_name, path)


def state_dir() -> Path:
    return Path(os.environ.get("TASKLIGHT_STATE_DIR", str(DEFAULT_STATE_DIR))).expanduser()


def output_path(root: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_UI_STATE_PATH", str(root / "ui_state.json"))).expanduser()


def health_path(root: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_STATE_PROJECTOR_HEALTH_PATH", str(root / "state_projector_health.json"))).expanduser()


def normalized_signals_path(root: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_NORMALIZED_SIGNALS_PATH", str(root / "normalized_signals.jsonl"))).expanduser()


def quota_state_path(root: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_QUOTA_STATE_PATH", str(root / "quota_state.json"))).expanduser()


def quota_probe_health_path(root: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_QUOTA_PROBE_HEALTH_PATH", str(root / "quota_probe_health.json"))).expanduser()


def quota_max_age_seconds() -> float:
    return float(os.environ.get("TASKLIGHT_QUOTA_STATE_MAX_AGE_SECONDS", "600"))


def quota_autoprobe_interval_seconds() -> float:
    return float(os.environ.get("TASKLIGHT_QUOTA_AUTOPROBE_INTERVAL_SECONDS", "120"))


def quota_autoprobe_timeout_seconds() -> float:
    return float(os.environ.get("TASKLIGHT_QUOTA_AUTOPROBE_TIMEOUT_SECONDS", "2"))


def quota_autoprobe_enabled(root: Path) -> bool:
    raw = os.environ.get("TASKLIGHT_QUOTA_AUTOPROBE")
    if raw is not None:
        return raw.lower() not in {"0", "false", "no", "off"}
    try:
        return root.expanduser().resolve() == DEFAULT_STATE_DIR.resolve()
    except OSError:
        return False


def signal_bus_max_age_seconds() -> float:
    return float(os.environ.get("TASKLIGHT_SIGNAL_BUS_MAX_AGE_SECONDS", "86400"))


def appserver_thread_active_ttl_seconds() -> float:
    return float(os.environ.get("TASKLIGHT_APPSERVER_THREAD_ACTIVE_TTL_SECONDS", "12"))


def appserver_thread_watcher_health_path(root: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_APPSERVER_THREAD_WATCHER_HEALTH_PATH", str(root / "appserver_thread_watcher_health.json"))).expanduser()


def current_thread_active_display_ttl_seconds() -> float:
    return float(
        os.environ.get(
            "TASKLIGHT_CURRENT_THREAD_ACTIVE_DISPLAY_TTL_SECONDS",
            os.environ.get("TASKLIGHT_CURRENT_TASK_ACTIVE_LEASE_SECONDS", "45"),
        )
    )


def normalize_signal(signal: dict[str, Any]) -> dict[str, Any]:
    identity = signal.get("identity") if isinstance(signal.get("identity"), dict) else {}
    occurred_at = signal.get("occurred_at") or signal.get("event_time") or signal.get("checked_at")
    return {
        "signal_id": signal.get("signal_id"),
        "source": signal.get("source"),
        "event_type": signal.get("event_type"),
        "task_id": signal.get("task_id") or identity.get("task_id"),
        "thread_id": signal.get("thread_id") or identity.get("thread_id"),
        "turn_id": signal.get("turn_id") or identity.get("turn_id"),
        "item_id": signal.get("item_id") or identity.get("item_id"),
        "pid": signal.get("pid") or identity.get("pid"),
        "observation_id": signal.get("observation_id") or identity.get("observation_id"),
        "status_hint": signal.get("status_hint"),
        "occurred_at": occurred_at,
        "confidence": float(signal.get("confidence") or 0.0),
        "thread_scoped": bool(signal.get("thread_scoped")),
        "turn_scoped": bool(signal.get("turn_scoped")),
        "source_quality": signal.get("source_quality"),
        "reason": signal.get("reason"),
        "message": signal.get("message"),
        "evidence": signal.get("evidence") or [],
        "appserver_activity_evidence": signal.get("appserver_activity_evidence") or [],
        "conflicts": signal.get("conflicts") or [],
        "raw_event_ref": signal.get("raw_event_ref"),
    }


def load_signal_bus(root: Path, max_records: int) -> tuple[list[dict[str, Any]], str]:
    path = normalized_signals_path(root)
    if not path.exists():
        return [], "missing"
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return [], "unreadable"
    signals: list[dict[str, Any]] = []
    cutoff = time.time() - signal_bus_max_age_seconds()
    for raw in lines[-max_records:]:
        if not raw.strip():
            continue
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            return [], "unreadable"
        if not isinstance(parsed, dict):
            continue
        signal = normalize_signal(parsed)
        signal_ts = parse_ts(signal.get("occurred_at"))
        if signal_ts is not None and signal_ts < cutoff:
            continue
        signals.append(signal)
    return signals, "readable"


def load_tasks(root: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    tasks_dir = root / "tasks"
    valid: list[dict[str, Any]] = []
    invalid: list[dict[str, Any]] = []
    if not tasks_dir.exists():
        return valid, invalid
    for path in sorted(tasks_dir.glob("*.json")):
        payload = load_json(path, None)
        if isinstance(payload, dict) and payload.get("task_id"):
            payload = dict(payload)
            payload["file_path"] = str(path)
            valid.append(payload)
        else:
            invalid.append(
                {
                    "task_id": path.stem,
                    "title": path.stem,
                    "status": "invalid_json",
                    "effective_status": "invalid_json",
                    "file_path": str(path),
                    "display_scope": "invalid",
                    "state_cause": "task_json:invalid_json",
                }
            )
    return valid, invalid


def load_bindings(root: Path) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]], dict[str, dict[str, Any]], list[dict[str, Any]]]:
    bindings_dir = root / "turn_bindings"
    by_task: dict[str, dict[str, Any]] = {}
    by_turn: dict[str, dict[str, Any]] = {}
    by_identity: dict[str, dict[str, Any]] = {}
    all_bindings: list[dict[str, Any]] = []
    if not bindings_dir.exists():
        return by_task, by_turn, by_identity, all_bindings
    for path in sorted(bindings_dir.glob("*.json")):
        payload = load_json(path, {})
        if not isinstance(payload, dict):
            continue
        payload = dict(payload)
        payload["file_path"] = str(path)
        all_bindings.append(payload)
        task_id = payload.get("task_id")
        turn_id = payload.get("turn_id")
        canonical_identity = payload.get("canonical_identity")
        aliases = payload.get("aliases") if isinstance(payload.get("aliases"), list) else []
        if task_id:
            by_task[str(task_id)] = payload
        if turn_id:
            by_turn[str(turn_id)] = payload
            by_identity.setdefault(f"turn:{turn_id}", payload)
        if canonical_identity:
            by_identity[str(canonical_identity)] = payload
        for alias in aliases:
            if alias:
                by_identity[str(alias)] = payload
    return by_task, by_turn, by_identity, all_bindings


def load_thread_bindings(root: Path) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]], list[dict[str, Any]]]:
    bindings_dir = root / "thread_bindings"
    by_task: dict[str, dict[str, Any]] = {}
    by_thread: dict[str, dict[str, Any]] = {}
    all_bindings: list[dict[str, Any]] = []
    if not bindings_dir.exists():
        return by_task, by_thread, all_bindings
    for path in sorted(bindings_dir.glob("*.json")):
        payload = load_json(path, {})
        if not isinstance(payload, dict):
            continue
        payload = dict(payload)
        payload["file_path"] = str(path)
        all_bindings.append(payload)
        task_id = payload.get("task_id")
        thread_id = payload.get("thread_id")
        if task_id:
            by_task[str(task_id)] = payload
        if thread_id:
            by_thread[str(thread_id)] = payload
    return by_task, by_thread, all_bindings


def load_observation_catalog(root: Path) -> list[dict[str, Any]]:
    state = load_json(root / "observations_state.json", {})
    records = state.get("observations") if isinstance(state, dict) else []
    if not isinstance(records, list):
        return []
    return [record for record in records if isinstance(record, dict)]


def load_ui_clients(root: Path) -> list[dict[str, Any]]:
    clients_dir = root / "ui_clients"
    clients: list[dict[str, Any]] = []
    if not clients_dir.exists():
        return clients
    for path in sorted(clients_dir.glob("*.json")):
        payload = load_json(path, {})
        if isinstance(payload, dict):
            payload = dict(payload)
            payload["file_path"] = str(path)
            clients.append(payload)
    return clients


def maybe_autoprobe_quota(root: Path, now_ts: float) -> None:
    if not quota_autoprobe_enabled(root):
        return
    health_path = quota_probe_health_path(root)
    health = load_json(health_path, {})
    last_probe_age = age_seconds((health or {}).get("last_probe_at"), now_ts) if isinstance(health, dict) else None
    if last_probe_age is not None and last_probe_age < quota_autoprobe_interval_seconds():
        return
    payload: dict[str, Any]
    try:
        from codex_quota_appserver_probe import read_rate_limits
        from codex_quota_import import normalize_appserver_response

        quota_payload = normalize_appserver_response(read_rate_limits(quota_autoprobe_timeout_seconds()))
        atomic_write_json(quota_state_path(root), quota_payload)
        payload = {
            "schema_version": SCHEMA_VERSION,
            "status": "ok",
            "source": "codex_appserver",
            "mode": "poll_fallback",
            "last_event_at": None,
            "last_probe_at": now_iso(),
            "quota_status": quota_payload.get("quota_status"),
            "effective_remaining_percent": quota_payload.get("effective_remaining_percent"),
            "last_error": None,
            "updated_at": now_iso(),
        }
    except Exception as error:
        payload = {
            "schema_version": SCHEMA_VERSION,
            "status": "error",
            "source": "codex_appserver",
            "mode": "poll_fallback",
            "last_event_at": None,
            "last_probe_at": now_iso(),
            "quota_status": "unknown",
            "effective_remaining_percent": None,
            "last_error": str(error)[:240],
            "updated_at": now_iso(),
        }
    atomic_write_json(health_path, payload)


def quota_display_bucket_priority(window: dict[str, Any]) -> tuple[int, int]:
    bucket_id = str(window.get("bucket_id") or "").lower()
    remaining = int(window.get("remaining_percent") or 0)
    if bucket_id == "codex":
        return (0, 0)
    if bucket_id.startswith("codex_"):
        return (2, remaining)
    if "codex" in bucket_id:
        return (1, remaining)
    return (3, remaining)


def select_quota_display_windows(windows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    valid = [window for window in windows if isinstance(window, dict) and isinstance(window.get("remaining_percent"), int)]
    grouped: dict[Any, list[dict[str, Any]]] = {}
    for window in valid:
        key = window.get("window_duration_mins") if window.get("window_duration_mins") is not None else window.get("label")
        grouped.setdefault(key, []).append(window)
    selected = [sorted(candidates, key=quota_display_bucket_priority)[0] for candidates in grouped.values()]
    selected.sort(key=lambda item: item.get("window_duration_mins") if item.get("window_duration_mins") is not None else 10**9)
    return selected


def project_quota_state(root: Path, now_ts: float) -> tuple[dict[str, Any] | None, dict[str, Any]]:
    path = quota_state_path(root)
    diagnostics = {
        "quota_state_path": str(path),
        "quota_probe_health_path": str(quota_probe_health_path(root)),
        "quota_status": "missing",
        "quota_fresh": False,
        "quota_source": None,
        "quota_probe_status": "disabled" if not quota_autoprobe_enabled(root) else "unknown",
        "quota_warning_count": 0,
    }
    if not path.exists():
        maybe_autoprobe_quota(root, now_ts)
    else:
        maybe_autoprobe_quota(root, now_ts)
    if not path.exists():
        health = load_json(quota_probe_health_path(root), {})
        if isinstance(health, dict):
            diagnostics["quota_probe_status"] = health.get("status", "unknown")
        return None, diagnostics
    payload = load_json(path, None)
    if not isinstance(payload, dict):
        diagnostics["quota_status"] = "invalid"
        return None, diagnostics
    captured_at = payload.get("captured_at")
    age = age_seconds(captured_at, now_ts)
    stale = age is None or age > quota_max_age_seconds()
    warnings = payload.get("warnings") if isinstance(payload.get("warnings"), list) else []
    raw_windows = payload.get("raw_windows") if isinstance(payload.get("raw_windows"), list) else []
    legacy_windows = payload.get("windows") if isinstance(payload.get("windows"), list) else []
    display_source = payload.get("display_windows") if isinstance(payload.get("display_windows"), list) else []
    raw_window_count = len(raw_windows) if raw_windows else len(legacy_windows)
    valid_windows = select_quota_display_windows(display_source) if display_source else select_quota_display_windows(legacy_windows)
    short = valid_windows[0] if valid_windows else {}
    long = valid_windows[-1] if len(valid_windows) > 1 else {}
    resets = payload.get("manual_resets") if isinstance(payload.get("manual_resets"), dict) else {}
    status = "unknown" if stale else str(payload.get("quota_status") or "unknown")
    if stale:
        maybe_autoprobe_quota(root, now_ts)
        refreshed = load_json(path, None)
        if isinstance(refreshed, dict) and refreshed.get("captured_at") != captured_at:
            return project_quota_state(root, time.time())
    health = load_json(quota_probe_health_path(root), {})
    probe_mode = health.get("mode") if isinstance(health, dict) else None
    diagnostics.update(
        {
            "quota_status": status,
            "quota_fresh": not stale,
            "quota_source": payload.get("source"),
            "quota_probe_status": health.get("status", "unknown") if isinstance(health, dict) else "unknown",
            "quota_probe_mode": probe_mode,
            "quota_warning_count": len(warnings),
            "quota_raw_window_count": raw_window_count,
        }
    )
    display_windows = [
        {
            "id": window.get("id"),
            "label": window.get("label"),
            "bucket_id": window.get("bucket_id"),
            "remaining_percent": None if stale else window.get("remaining_percent"),
            "used_percent": window.get("used_percent"),
            "reset_label": window.get("reset_label"),
            "window_duration_mins": window.get("window_duration_mins"),
            "health": "unknown" if stale else window.get("health"),
            "selection_reason": window.get("selection_reason"),
        }
        for window in valid_windows
    ]
    quota = {
        "source": payload.get("source"),
        "fresh": not stale,
        "status": status,
        "effective_remaining_percent": None if stale else payload.get("effective_remaining_percent"),
        "display_windows": display_windows,
        "raw_window_count": raw_window_count,
        "captured_age_sec": age,
        "probe_mode": probe_mode,
        "bucket_id": short.get("bucket_id"),
        "warnings": warnings,
        "short_percent": None if stale else short.get("remaining_percent"),
        "short_label": short.get("label"),
        "short_reset_label": short.get("reset_label"),
        "short_bucket_id": short.get("bucket_id"),
        "long_percent": None if stale else long.get("remaining_percent"),
        "long_label": long.get("label"),
        "long_reset_label": long.get("reset_label"),
        "long_bucket_id": long.get("bucket_id"),
        "manual_resets_available": None if stale else resets.get("available_count"),
        "captured_at": captured_at,
        "recommendation": payload.get("recommendation"),
    }
    return quota, diagnostics


def task_timestamp(task: dict[str, Any]) -> Any:
    return task.get("updated_at") or task.get("heartbeat_at") or task.get("started_at") or task.get("created_at")


def done_timestamp(task: dict[str, Any]) -> Any:
    return task.get("verified_at") or task.get("done_at") or task.get("updated_at") or task.get("started_at") or task.get("created_at")


def short_hash(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:12]


def make_signal(source: str, event_type: str, *, identity: dict[str, Any], confidence: float, occurred_at: Any, status_hint: str) -> dict[str, Any]:
    stable = {
        "source": source,
        "event_type": event_type,
        "identity": identity,
        "occurred_at": occurred_at,
        "status_hint": status_hint,
    }
    return {
        "signal_id": "sig_" + short_hash(json.dumps(stable, ensure_ascii=True, sort_keys=True, default=str)),
        "source": source,
        "identity": identity,
        "event_type": event_type,
        "status_hint": status_hint,
        "confidence": confidence,
        "occurred_at": occurred_at,
    }


def is_hook_projected_task(task: dict[str, Any], binding: dict[str, Any] | None) -> bool:
    if binding is not None:
        return True
    title = str(task.get("title") or "").lower()
    return title.startswith("codex turn ")


def signal_age(signal: dict[str, Any] | None, now_ts: float) -> float | None:
    if not signal:
        return None
    return age_seconds(signal.get("occurred_at"), now_ts)


def _string_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item) for item in value if item is not None]
    if value is None:
        return []
    return [str(value)]


def appserver_activity_evidence(signal: dict[str, Any]) -> list[str]:
    evidence = _string_list(signal.get("appserver_activity_evidence"))
    if evidence:
        return evidence
    return [
        item
        for item in _string_list(signal.get("evidence"))
        if "status=active" in item.lower() or "turn/started" in item.lower() or "item/started" in item.lower()
    ]


def is_appserver_active_like_signal(signal: dict[str, Any], *, age: float | None, ttl: float) -> tuple[bool, str | None, str | None, list[str]]:
    if str(signal.get("source") or "") != "codex_appserver":
        return False, None, "not_appserver", []
    evidence = appserver_activity_evidence(signal)
    event_type = str(signal.get("event_type") or "").lower()
    status_hint = str(signal.get("status_hint") or "").lower()
    source_quality = str(signal.get("source_quality") or "").lower()
    evidence_text = " ".join(_string_list(signal.get("evidence")) + evidence).lower()
    if age is None:
        return False, None, "missing_event_time", evidence
    if age > ttl:
        return False, None, "stale_appserver_signal", evidence
    if event_type in {"unknown", "appserver_quiet"}:
        return False, None, f"event_type={event_type}", evidence
    if status_hint in {"unknown", "notloaded", "not_loaded", "idle", "quiet", "complete", "completed"}:
        return False, None, f"status_hint={status_hint}", evidence
    if any(marker in source_quality for marker in ("unknown", "ignored", "quiet")):
        return False, None, f"source_quality={source_quality}", evidence
    ignored_evidence_markers = (
        "status=notloaded",
        "status=not_loaded",
        "status=unknown",
        "status=idle",
        "status=complete",
        "status=completed",
    )
    if not evidence and any(marker in evidence_text for marker in ignored_evidence_markers):
        return False, None, "thread_list_idle_or_unknown", evidence
    if event_type in {"turn_started", "item_started"}:
        return True, f"event_type={event_type}", None, evidence or [f"event_type={event_type}"]
    if "status=active" in evidence_text or status_hint in {"active", "running"}:
        return True, "thread_list_status_active", None, evidence or ["thread/list:status=active"]
    if evidence:
        return True, "appserver_activity_evidence", None, evidence
    return False, None, "missing_active_like_evidence", evidence


def unique_signals(signals: list[dict[str, Any]]) -> list[dict[str, Any]]:
    deduped: dict[str, dict[str, Any]] = {}
    ordered: list[dict[str, Any]] = []
    for signal in signals:
        signal_id = str(signal.get("signal_id") or "")
        if signal_id and signal_id in deduped:
            continue
        if signal_id:
            deduped[signal_id] = signal
        ordered.append(signal)
    return ordered


def turn_id_from_identity(identity: Any, *, thread_id: str = "") -> str | None:
    if not identity:
        return None
    value = str(identity)
    if value.startswith("turn:"):
        suffix = value.split(":", 1)[1]
        return suffix or None
    if thread_id and value.startswith(f"{thread_id}:"):
        suffix = value[len(thread_id) + 1 :]
        if suffix and not suffix.startswith("epoch-"):
            return suffix
    return None


def binding_turn_id(binding: dict[str, Any] | None) -> str | None:
    if not isinstance(binding, dict):
        return None
    raw_turn_id = binding.get("turn_id")
    if raw_turn_id:
        return str(raw_turn_id)
    thread_id = str(binding.get("thread_id") or "")
    for key in ("canonical_identity", "task_identity"):
        turn_id = turn_id_from_identity(binding.get(key), thread_id=thread_id)
        if turn_id:
            return turn_id
    return None


def relevant_task_signals(
    task: dict[str, Any],
    binding: dict[str, Any] | None,
    thread_binding: dict[str, Any] | None,
    *,
    signals_by_task: dict[str, list[dict[str, Any]]],
    signals_by_turn: dict[str, list[dict[str, Any]]],
    signals_by_thread: dict[str, list[dict[str, Any]]],
) -> list[dict[str, Any]]:
    task_id = str(task.get("task_id") or "")
    turn_id = str(binding_turn_id(binding) or binding_turn_id(thread_binding) or "")
    thread_id = str((thread_binding or {}).get("thread_id") or "")
    matches: list[dict[str, Any]] = []
    if task_id:
        matches.extend(signals_by_task.get(task_id, []))
    if turn_id:
        matches.extend(signals_by_turn.get(turn_id, []))
    if thread_id:
        matches.extend(signals_by_thread.get(thread_id, []))
    matches = unique_signals(matches)
    matches.sort(key=lambda item: parse_ts(item.get("occurred_at")) or 0)
    return matches


def task_binding_identity(task: dict[str, Any], binding: dict[str, Any] | None) -> tuple[str | None, list[str]]:
    canonical = None
    aliases: list[str] = []
    if isinstance(binding, dict):
        raw_canonical = binding.get("canonical_identity")
        canonical = str(raw_canonical) if raw_canonical else None
        raw_aliases = binding.get("aliases")
        if isinstance(raw_aliases, list):
            aliases = [str(alias) for alias in raw_aliases if alias]
    if canonical is None:
        turn_id = binding_turn_id(binding) or task.get("turn_id")
        if turn_id:
            canonical = f"turn:{turn_id}"
    return canonical, aliases


def latest_matching(signals: list[dict[str, Any]], event_types: set[str]) -> dict[str, Any] | None:
    for signal in reversed(signals):
        if str(signal.get("event_type") or "") in event_types:
            return signal
    return None


def latest_matching_source(
    signals: list[dict[str, Any]],
    *,
    source: str,
    event_types: set[str] | None = None,
) -> dict[str, Any] | None:
    for signal in reversed(signals):
        if str(signal.get("source") or "") != source:
            continue
        if event_types is not None and str(signal.get("event_type") or "") not in event_types:
            continue
        return signal
    return None


def latest_signal_for_key(signals: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not signals:
        return None
    return max(signals, key=lambda item: parse_ts(item.get("occurred_at")) or 0.0)


def signal_status_hint(signal: dict[str, Any]) -> str:
    event_type = str(signal.get("event_type") or "")
    status_hint = str(signal.get("status_hint") or "")
    if event_type in VERIFIED_SIGNAL_EVENTS:
        return "done_verified"
    if event_type in BLOCK_SIGNAL_EVENTS:
        return "blocked"
    if event_type in DONE_SIGNAL_EVENTS:
        return "done_unverified"
    if event_type in RELEASE_SIGNAL_EVENTS:
        return "cancelled"
    if status_hint in {"blocked", "done_unverified", "done_verified", "cancelled", "running", "queued", "stale"}:
        return status_hint
    if event_type in ACTIVE_SIGNAL_EVENTS:
        return "running"
    return status_hint or "running"


def synthesize_tasks_from_signals(
    tasks: list[dict[str, Any]],
    *,
    bindings_by_turn: dict[str, dict[str, Any]],
    bus_signals: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    existing_task_ids = {str(task.get("task_id") or "") for task in tasks if task.get("task_id")}
    grouped: dict[str, dict[str, Any]] = {}

    for signal in bus_signals:
        turn_id = str(signal.get("turn_id") or "")
        binding = bindings_by_turn.get(turn_id) if turn_id else None
        task_id = str(signal.get("task_id") or (binding or {}).get("task_id") or "")
        if not task_id or task_id in existing_task_ids:
            continue
        bucket = grouped.setdefault(task_id, {"signals": [], "binding": binding})
        bucket["signals"].append(signal)
        if binding is not None:
            bucket["binding"] = binding

    synthetic: list[dict[str, Any]] = []
    for task_id, bucket in grouped.items():
        signals = bucket["signals"]
        binding = bucket.get("binding") if isinstance(bucket.get("binding"), dict) else None
        latest_signal = latest_signal_for_key(signals)
        if latest_signal is None:
            continue
        turn_id = str(latest_signal.get("turn_id") or (binding or {}).get("turn_id") or "")
        title = str(
            (binding or {}).get("title")
            or (f"Codex turn {turn_id[:8]}" if turn_id else task_id)
        )
        status = signal_status_hint(latest_signal)
        occurred_at = latest_signal.get("occurred_at") or now_iso()
        synthetic.append(
            {
                "schema_version": 3,
                "task_id": task_id,
                "short_task_id": task_id[-8:],
                "title": title,
                "canonical_identity": f"turn:{turn_id}" if turn_id else None,
                "binding_aliases": list((binding or {}).get("aliases") or []),
                "slug": title.lower().replace(" ", "-")[:48],
                "status": status,
                "raw_status": status,
                "effective_status": status,
                "phase": str((binding or {}).get("phase") or latest_signal.get("event_type") or "signal"),
                "progress": None,
                "reason": latest_signal.get("reason"),
                "message": latest_signal.get("message"),
                "summary": "Signal bus synthesized task",
                "created_at": occurred_at,
                "started_at": occurred_at,
                "updated_at": occurred_at,
                "heartbeat_at": occurred_at if status in {"running", "queued", "stale"} else None,
                "done_at": occurred_at if status in {"done_unverified", "done_verified"} else None,
                "verified_at": occurred_at if status == "done_verified" else None,
                "source": latest_signal.get("source") or "signal_bus",
                "file_path": None,
            }
        )
    return tasks + synthetic


def binding_is_fresh(binding: dict[str, Any] | None, now_ts: float, ttl: float) -> bool:
    if not binding or binding.get("status") != "active":
        return False
    last_age = age_seconds(binding.get("last_signal_at") or binding.get("updated_at"), now_ts)
    return last_age is not None and last_age <= ttl


def classify_task(
    task: dict[str, Any],
    binding: dict[str, Any] | None,
    thread_binding: dict[str, Any] | None,
    *,
    now_ts: float,
    hook_active_ttl: float,
    current_thread_active_ttl: float,
    completed_idle_seconds: float,
    hook_turn_lease_seconds: float,
    verification_ttl: float,
    done_visible_hours: float,
    signals_by_task: dict[str, list[dict[str, Any]]],
    signals_by_turn: dict[str, list[dict[str, Any]]],
    signals_by_thread: dict[str, list[dict[str, Any]]],
    signal_bus_has_records: bool,
) -> tuple[dict[str, Any], dict[str, Any]]:
    raw_status = str(task.get("raw_status") or task.get("status") or task.get("effective_status") or "idle")
    effective_status = str(task.get("effective_status") or task.get("status") or raw_status)
    if effective_status == "done_unverified":
        done_age = age_seconds(done_timestamp(task), now_ts)
        if done_age is not None and done_age > verification_ttl:
            effective_status = "stale"
    source = "codex_hook" if is_hook_projected_task(task, binding) else str(task.get("source") or "tasklight")
    last_signal_event = (binding or {}).get("last_signal_event")
    task_signals = relevant_task_signals(
        task,
        binding,
        thread_binding,
        signals_by_task=signals_by_task,
        signals_by_turn=signals_by_turn,
        signals_by_thread=signals_by_thread,
    )
    latest_signal = task_signals[-1] if task_signals else None
    latest_active = latest_matching(task_signals, ACTIVE_SIGNAL_EVENTS)
    latest_block = latest_matching(task_signals, BLOCK_SIGNAL_EVENTS)
    latest_done = latest_matching(task_signals, DONE_SIGNAL_EVENTS)
    latest_verified = latest_matching(task_signals, VERIFIED_SIGNAL_EVENTS)
    latest_release = latest_matching(task_signals, RELEASE_SIGNAL_EVENTS)
    latest_current_thread_signal = latest_matching_source(
        task_signals,
        source="current_thread_watcher",
        event_types=ACTIVE_SIGNAL_EVENTS,
    )
    latest_private_thread_probe = latest_matching_source(
        task_signals,
        source="codex_private_probe",
        event_types={"private_active"},
    )
    latest_active_age = signal_age(latest_active, now_ts)
    latest_block_age = signal_age(latest_block, now_ts)
    latest_current_thread_age = signal_age(latest_current_thread_signal, now_ts)
    latest_private_thread_probe_age = signal_age(latest_private_thread_probe, now_ts)
    signal_backed = bool(task_signals)
    display_scope = "history"
    state_cause = f"task:{effective_status}"
    fresh = False
    confidence = 0.80

    if latest_signal and latest_signal.get("source") == "explicit":
        source = "explicit"
    elif thread_binding is not None and source == "tasklight":
        source = "current_thread"

    if source == "codex_hook" and raw_status in {"running", "queued", "stale", "blocked"}:
        confidence = 0.95
        blocker_resolved = (
            latest_verified is not None
            or latest_done is not None
            or latest_release is not None
        )
        if effective_status in {"blocked", "stale"}:
            if blocker_resolved:
                display_scope = "resolved_blocker"
                state_cause = "hook:blocker_resolved"
            elif effective_status == "blocked" and latest_block_age is not None and latest_block_age <= hook_turn_lease_seconds and binding_is_fresh(binding, now_ts, hook_turn_lease_seconds):
                display_scope = "open_blocker"
                state_cause = "hook:blocker_fresh"
            else:
                display_scope = "stale_blocker"
                state_cause = "hook:blocker_stale" if effective_status == "blocked" else "hook:stale_diagnostic"
        elif latest_active is not None and latest_active_age is not None and latest_active_age <= hook_active_ttl and binding_is_fresh(binding, now_ts, hook_turn_lease_seconds):
            fresh = True
            signal_event = str(latest_active.get("event_type") or last_signal_event or "active")
            if signal_event == "item_completed" and latest_active_age > completed_idle_seconds:
                display_scope = "released"
                state_cause = "hook:item_completed_idle_timeout"
            else:
                display_scope = "active_execution"
                state_cause = f"hook:{signal_event}"
        else:
            display_scope = "released"
            state_cause = "hook:not_fresh"
    elif source == "current_thread" and raw_status in {"running", "queued", "stale"}:
        confidence = 0.88
        binding_fresh = binding_is_fresh(thread_binding, now_ts, current_thread_active_ttl)
        thread_binding_turn_id = binding_turn_id(thread_binding)
        latest_release_age = signal_age(latest_release, now_ts)
        private_probe_fresh = (
            latest_private_thread_probe is not None
            and latest_private_thread_probe_age is not None
            and latest_private_thread_probe_age <= current_thread_active_ttl
            and bool(latest_private_thread_probe.get("thread_scoped"))
            and float(latest_private_thread_probe.get("confidence") or 0.0) >= 0.70
            and str(latest_private_thread_probe.get("source_quality") or "") != "global_private_metadata"
        )
        if (
            latest_current_thread_signal is not None
            and latest_current_thread_age is not None
            and latest_current_thread_age <= current_thread_active_ttl
            and binding_fresh
            and (private_probe_fresh or bool(thread_binding_turn_id))
        ):
            fresh = True
            display_scope = "active_execution"
            signal_event = str(latest_current_thread_signal.get("event_type") or "heartbeat")
            if private_probe_fresh:
                state_cause = f"current_thread:{signal_event}"
            else:
                state_cause = f"current_thread:turn_anchored_{signal_event}"
        elif latest_release is not None and latest_release_age is not None:
            display_scope = "released"
            state_cause = f"current_thread:{str(latest_release.get('reason') or 'released')}"
        elif thread_binding is not None and thread_binding.get("status") == "released":
            display_scope = "released"
            state_cause = f"current_thread:{str(thread_binding.get('released_at') and 'binding_released' or 'released')}"
        elif binding_fresh and latest_current_thread_signal is not None and latest_current_thread_age is not None and latest_current_thread_age <= current_thread_active_ttl:
            display_scope = "released"
            state_cause = "current_thread:compat_without_thread_probe"
        else:
            display_scope = "released"
            state_cause = "current_thread:not_fresh"
    elif signal_bus_has_records and not signal_backed and effective_status in {"blocked", "stale", "running", "queued", "done_unverified"}:
        confidence = 0.35
        if effective_status == "blocked":
            display_scope = "resolved_blocker"
        elif effective_status == "stale":
            display_scope = "stale_blocker"
        elif effective_status == "done_unverified":
            display_scope = "history"
        else:
            display_scope = "released"
        state_cause = f"compat:no_signal:{effective_status}"
    elif effective_status == "blocked":
        display_scope = "open_blocker"
        state_cause = "task:blocked"
        confidence = 1.0
    elif effective_status == "stale":
        display_scope = "stale_blocker"
        state_cause = "task:stale"
        confidence = 0.90
    elif effective_status in {"running", "queued"}:
        display_scope = "active_execution"
        state_cause = f"task:{effective_status}"
        confidence = 0.98
        fresh = True
    elif effective_status == "done_unverified":
        display_scope = "pending_verify"
        state_cause = "task:done_unverified"
        confidence = 0.98
    elif effective_status == "done_verified":
        done_age = age_seconds(done_timestamp(task), now_ts)
        if done_age is not None and done_age <= max(0.0, done_visible_hours) * 3600:
            display_scope = "recent_done"
        else:
            display_scope = "history"
        state_cause = "task:done_verified"
        confidence = 1.0
    elif effective_status == "cancelled":
        display_scope = "released"
        state_cause = "task:cancelled"
    elif effective_status == "invalid_json":
        display_scope = "invalid"
        state_cause = "task:invalid_json"
        confidence = 0.40

    task_id = str(task.get("task_id") or "")
    projected = {
        "task_id": task_id,
        "short_task_id": task.get("short_task_id") or task_id[-8:],
        "title": task.get("title") or task_id,
        "turn_id": binding_turn_id(binding) or binding_turn_id(thread_binding),
        "source": source,
        "raw_status": raw_status,
        "effective_status": effective_status,
        "display_scope": display_scope if display_scope in DISPLAY_SCOPES else "history",
        "last_signal_age_sec": None if signal_age(latest_signal, now_ts) is None else round(signal_age(latest_signal, now_ts) or 0, 2),
        "state_cause": state_cause,
        "fresh": fresh,
        "phase": task.get("phase") or (binding or {}).get("phase"),
        "progress": task.get("progress"),
        "reason": task.get("reason"),
        "message": task.get("message"),
        "summary": task.get("summary"),
        "started_at": task.get("started_at"),
        "updated_at": task.get("updated_at"),
        "done_at": task.get("done_at"),
        "verified_at": task.get("verified_at"),
        "file_path": task.get("file_path"),
        "confidence": confidence,
    }
    canonical_identity, binding_aliases = task_binding_identity(task, binding)
    projected["canonical_identity"] = canonical_identity
    projected["binding_aliases"] = binding_aliases
    signal = make_signal(
        source,
        state_cause,
        identity={"task_id": task_id, "turn_id": projected["turn_id"], "thread_id": (binding or {}).get("thread_id"), "pid": None},
        confidence=confidence,
        occurred_at=(latest_signal or {}).get("occurred_at") or (binding or {}).get("last_signal_at") or task_timestamp(task),
        status_hint=projected["effective_status"],
    )
    return projected, signal


def observation_allowed(record: dict[str, Any]) -> bool:
    command = str(record.get("command") or record.get("command_short") or "").lower()
    return not any(snippet in command for snippet in OBSERVED_EXCLUDE_SNIPPETS)


def project_observations_legacy(records: list[dict[str, Any]], now_ts: float, observed_ttl: float) -> tuple[list[dict[str, Any]], list[dict[str, Any]], int]:
    projected: list[dict[str, Any]] = []
    signals: list[dict[str, Any]] = []
    false_positive_count = 0
    for record in records:
        seen_age = age_seconds(record.get("last_seen_at") or record.get("detected_at"), now_ts)
        fresh = seen_age is not None and seen_age <= observed_ttl
        confidence = float(record.get("confidence") or 0.0)
        allowed = observation_allowed(record)
        if not allowed:
            false_positive_count += 1
        status = str(record.get("status") or "observed_quiet")
        display_scope = "observed_only" if status == "observed_active" and fresh and confidence >= 0.35 and allowed else "history"
        item = {
            "observation_id": record.get("observation_id"),
            "title": record.get("title") or "Observed thread",
            "status": status,
            "confidence": confidence,
            "display_scope": display_scope,
            "fresh": fresh,
            "last_seen_age_sec": None if seen_age is None else round(seen_age, 2),
            "pid": record.get("pid"),
            "command_short": record.get("command_short"),
            "cwd": record.get("cwd"),
            "last_seen_at": record.get("last_seen_at"),
            "source": "process_observer",
        }
        projected.append(item)
        signals.append(
            make_signal(
                "process_observer",
                status,
                identity={"task_id": None, "turn_id": None, "thread_id": None, "pid": record.get("pid")},
                confidence=confidence,
                occurred_at=record.get("last_seen_at"),
                status_hint=status,
            )
        )
    return projected, signals, false_positive_count


def project_observations(
    records: list[dict[str, Any]],
    bus_signals: list[dict[str, Any]],
    now_ts: float,
    observed_ttl: float,
    signal_bus_has_records: bool,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], int]:
    catalog_by_observation_id = {
        str(record.get("observation_id")): record
        for record in records
        if record.get("observation_id")
    }
    latest_by_identity: dict[str, dict[str, Any]] = {}
    for signal in bus_signals:
        if str(signal.get("source") or "") != "process_observer":
            continue
        observation_id = str(signal.get("observation_id") or "")
        pid = signal.get("pid")
        identity = observation_id or (f"pid:{pid}" if pid is not None else "")
        if not identity:
            continue
        previous = latest_by_identity.get(identity)
        previous_ts = parse_ts((previous or {}).get("occurred_at"))
        current_ts = parse_ts(signal.get("occurred_at"))
        if previous is None or (current_ts or 0.0) >= (previous_ts or 0.0):
            latest_by_identity[identity] = signal

    if not latest_by_identity:
        if signal_bus_has_records:
            projected, signals, false_positive_count = project_observations_legacy(records, now_ts, observed_ttl)
            for item in projected:
                item["display_scope"] = "history"
                item["fresh"] = False
            return projected, signals, false_positive_count
        return project_observations_legacy(records, now_ts, observed_ttl)

    projected: list[dict[str, Any]] = []
    synthesized_signals: list[dict[str, Any]] = []
    false_positive_count = 0

    for identity, signal in sorted(latest_by_identity.items()):
        observation_id = str(signal.get("observation_id") or "")
        record = catalog_by_observation_id.get(observation_id, {})
        seen_age = signal_age(signal, now_ts)
        fresh = seen_age is not None and seen_age <= observed_ttl
        confidence = float(signal.get("confidence") or 0.0)
        status = str(signal.get("event_type") or signal.get("status_hint") or "observed_quiet")
        command = str(record.get("command") or record.get("command_short") or signal.get("message") or "")
        allowed = observation_allowed({"command": command})
        if not allowed:
            false_positive_count += 1
        display_scope = "observed_only" if status == "observed_active" and fresh and confidence >= 0.35 and allowed else "history"
        projected.append(
            {
                "observation_id": observation_id or identity,
                "title": record.get("title") or f"Observed {identity}",
                "status": status,
                "confidence": confidence,
                "display_scope": display_scope,
                "fresh": fresh,
                "last_seen_age_sec": None if seen_age is None else round(seen_age, 2),
                "pid": signal.get("pid") or record.get("pid"),
                    "command_short": record.get("command_short") or command or None,
                    "cwd": record.get("cwd"),
                    "last_seen_at": signal.get("occurred_at") or record.get("last_seen_at"),
                    "source": "process_observer",
                }
            )
        synthesized_signals.append(
            make_signal(
                "process_observer",
                status,
                identity={
                    "task_id": None,
                    "turn_id": None,
                    "thread_id": None,
                    "pid": signal.get("pid") or record.get("pid"),
                    "observation_id": observation_id or identity,
                },
                confidence=confidence,
                occurred_at=signal.get("occurred_at") or record.get("last_seen_at"),
                status_hint=status,
            )
        )

    return projected, synthesized_signals, false_positive_count


def project_appserver_thread_observations(
    signals: list[dict[str, Any]],
    *,
    now_ts: float,
    active_ttl: float,
    current_thread_id: str | None,
    active_task_thread_ids: set[str],
    ) -> tuple[list[dict[str, Any]], int, float | None]:
    latest_by_thread: dict[str, dict[str, Any]] = {}
    for signal in signals:
        if str(signal.get("source") or "") != "codex_appserver":
            continue
        thread_id = str(signal.get("thread_id") or "")
        if not thread_id:
            continue
        previous = latest_by_thread.get(thread_id)
        previous_ts = parse_ts((previous or {}).get("occurred_at"))
        current_ts = parse_ts(signal.get("occurred_at"))
        if previous is None or (current_ts or 0.0) >= (previous_ts or 0.0):
            latest_by_thread[thread_id] = signal

    projected: list[dict[str, Any]] = []
    active_count = 0
    latest_age: float | None = None
    for thread_id, signal in sorted(latest_by_thread.items()):
        if current_thread_id and thread_id == current_thread_id:
            continue
        if thread_id in active_task_thread_ids:
            continue
        source_quality = str(signal.get("source_quality") or "")
        event_type = str(signal.get("event_type") or "")
        fresh_age = signal_age(signal, now_ts)
        fresh = fresh_age is not None and fresh_age <= active_ttl
        active_like, why_active, why_ignored, evidence = is_appserver_active_like_signal(signal, age=fresh_age, ttl=active_ttl)
        if not fresh:
            display_scope = "history"
            status = "observed_quiet"
            confidence = 0.0
        elif active_like:
            display_scope = "observed_active_high_confidence"
            status = "observed_active"
            confidence = max(0.72 if source_quality.startswith("codex_appserver_thread_list") else 0.95, float(signal.get("confidence") or 0.0))
        else:
            display_scope = "history"
            status = "observed_quiet"
            confidence = float(signal.get("confidence") or 0.0)

        if display_scope in {"active_execution", "observed_active_high_confidence"}:
            active_count += 1
            latest_age = fresh_age if latest_age is None else min(latest_age, fresh_age or latest_age)

        projected.append(
            {
                "observation_id": f"appserver:{thread_id}",
                "title": f"Codex thread {thread_id[:8]}",
                "status": status,
                "confidence": confidence,
                "display_scope": display_scope,
                "fresh": fresh,
                "last_seen_age_sec": None if fresh_age is None else round(fresh_age, 2),
                "pid": None,
                "command_short": "codex app-server thread/list",
                "cwd": None,
                "last_seen_at": signal.get("occurred_at"),
                "source": "codex_appserver",
                "state_cause": f"codex_appserver:{event_type}",
                "why_active": why_active,
                "why_ignored": why_ignored,
                "appserver_activity_evidence": evidence,
            }
        )
    return projected, active_count, None if latest_age is None else round(latest_age, 2)


def build_counts(tasks: list[dict[str, Any]], observations: list[dict[str, Any]]) -> dict[str, int]:
    counts = {
        "blocked": 0,
        "stale": 0,
        "running": 0,
        "queued": 0,
        "pending_verify_count": 0,
        "done_verified_visible": 0,
        "observed_active": 0,
        "appserver_active": 0,
        "process_observed": 0,
        "managed_active": 0,
    }
    for task in tasks:
        scope = task.get("display_scope")
        status = task.get("effective_status")
        if scope == "open_blocker":
            counts["blocked"] += 1
            counts["managed_active"] += 1
        elif scope == "stale_blocker":
            counts["stale"] += 1
        elif scope == "active_execution":
            if status == "queued":
                counts["queued"] += 1
            else:
                counts["running"] += 1
            counts["managed_active"] += 1
        elif scope == "pending_verify":
            counts["pending_verify_count"] += 1
            counts["managed_active"] += 1
        elif scope == "recent_done":
            counts["done_verified_visible"] += 1
    visible_observed_scopes = {"active_execution", "observed_active_high_confidence", "observed_only"}
    for item in observations:
        if item.get("display_scope") not in visible_observed_scopes:
            continue
        source = str(item.get("source") or "")
        observation_id = str(item.get("observation_id") or "")
        if source == "codex_appserver" or observation_id.startswith("appserver:"):
            counts["appserver_active"] += 1
        else:
            counts["process_observed"] += 1
    counts["observed_active"] = counts["appserver_active"] + counts["process_observed"]
    return counts


def global_from_projection(
    tasks: list[dict[str, Any]],
    counts: dict[str, int],
    runtime_candidates: list[dict[str, Any]],
) -> tuple[str, str, float, list[str]]:
    reasons: list[str] = []
    open_blockers = [task for task in tasks if task.get("display_scope") == "open_blocker"]
    active_tasks = [task for task in tasks if task.get("display_scope") == "active_execution"]
    pending_tasks = [task for task in tasks if task.get("display_scope") == "pending_verify"]
    active_runtime = [candidate for candidate in runtime_candidates if candidate.get("display_scope") == "active_execution"]
    appserver_observed_runtime = [
        candidate
        for candidate in runtime_candidates
        if candidate.get("display_scope") == "observed_active_high_confidence"
        and "codex_appserver" in set(candidate.get("source_set") or [])
    ]
    if open_blockers:
        reasons.append("open_blocker")
        return "blocked", "BLOCKED", max(float(task.get("confidence") or 0.9) for task in open_blockers), reasons
    if active_tasks:
        reasons.append("active_execution")
        return "running", "RUNNING", max(float(task.get("confidence") or 0.95) for task in active_tasks), reasons
    if active_runtime:
        reasons.append("runtime_candidate:active_execution")
        return "running", "RUNNING", max(float(item.get("runtime_score") or 0.85) for item in active_runtime), reasons
    if appserver_observed_runtime:
        reasons.append("runtime_candidate:codex_appserver")
        return "running", "RUNNING", max(float(item.get("runtime_score") or 0.55) for item in appserver_observed_runtime), reasons
    if pending_tasks:
        reasons.append("pending_verify")
        return "pending", "PENDING", 0.98, reasons
    if counts["done_verified_visible"] > 0:
        reasons.append("recent_done")
        return "done_verified", "DONE", 1.0, reasons
    reasons.append("no_active_ui_scope")
    return "idle", "IDLE", 1.0, reasons


def latest_active_turn_age(bindings: list[dict[str, Any]], now_ts: float) -> float | None:
    ages = [
        age_seconds(binding.get("last_signal_at") or binding.get("updated_at"), now_ts)
        for binding in bindings
        if binding.get("status") == "active"
    ]
    ages = [age for age in ages if age is not None]
    return None if not ages else round(min(ages), 2)


def latest_observed_age(observations: list[dict[str, Any]]) -> float | None:
    ages = [item.get("last_seen_age_sec") for item in observations if item.get("last_seen_age_sec") is not None]
    return None if not ages else round(min(float(age) for age in ages), 2)


def latest_binding(bindings: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not bindings:
        return None
    return sorted(
        bindings,
        key=lambda item: parse_ts(item.get("updated_at") or item.get("created_at")) or 0.0,
        reverse=True,
    )[0]


def binding_canonical_identity(binding: dict[str, Any] | None) -> str | None:
    if not isinstance(binding, dict):
        return None
    canonical = binding.get("canonical_identity")
    if canonical:
        return str(canonical)
    turn_id = binding.get("turn_id")
    if turn_id:
        return f"turn:{turn_id}"
    return None


def latest_current_thread_signal_age(bus_signals: list[dict[str, Any]], now_ts: float) -> float | None:
    ages = [
        age_seconds(signal.get("occurred_at"), now_ts)
        for signal in bus_signals
        if str(signal.get("source") or "") == "current_thread_watcher"
        and age_seconds(signal.get("occurred_at"), now_ts) is not None
    ]
    return None if not ages else round(min(ages), 2)


def latest_signal_by_source(bus_signals: list[dict[str, Any]], source: str) -> dict[str, Any] | None:
    matches = [signal for signal in bus_signals if str(signal.get("source") or "") == source]
    if not matches:
        return None
    return max(matches, key=lambda item: parse_ts(item.get("occurred_at")) or 0.0)


def signal_source_counts(bus_signals: list[dict[str, Any]]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for signal in bus_signals:
        source = str(signal.get("source") or "unknown")
        counts[source] = counts.get(source, 0) + 1
    return dict(sorted(counts.items()))


def latest_signal_age_for_source(bus_signals: list[dict[str, Any]], source: str, now_ts: float) -> float | None:
    latest = latest_signal_by_source(bus_signals, source)
    age = signal_age(latest, now_ts)
    return None if age is None else round(age, 2)


def latest_ui_client(clients: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not clients:
        return None
    return sorted(clients, key=lambda item: parse_ts(item.get("updated_at") or item.get("started_at")) or 0, reverse=True)[0]


def freshness_score(age: float | None, ttl: float) -> float:
    if age is None or ttl <= 0:
        return 0.0
    if age <= ttl:
        return 1.0
    if age <= 2 * ttl:
        return 0.5
    return 0.0


def signal_identity_score(signal: dict[str, Any], config: dict[str, Any]) -> float:
    scores = config.get("identity_score", {}) if isinstance(config.get("identity_score"), dict) else {}
    if signal.get("turn_id"):
        return float(scores.get("turn_id", 1.0))
    if signal.get("thread_id"):
        return float(scores.get("thread_id", 0.8))
    if signal.get("pid") or signal.get("observation_id"):
        return float(scores.get("pid_cwd_only", 0.4))
    return float(scores.get("global_only", 0.2))


def base_confidence_for_signal(signal: dict[str, Any], config: dict[str, Any]) -> float:
    source = str(signal.get("source") or "")
    event_type = str(signal.get("event_type") or "")
    source_quality = str(signal.get("source_quality") or "")
    base = config.get("base_confidence", {}) if isinstance(config.get("base_confidence"), dict) else {}
    if source == "explicit":
        return float(base.get("explicit_tasklight", 1.0))
    if source in {"tasklight", "wrapper"}:
        return float(base.get("wrapper_managed_task", 0.98))
    if source == "codex_hook" and signal.get("turn_id"):
        return float(base.get("codex_hook_turn", 0.95))
    if source == "codex_appserver":
        event_type = str(signal.get("event_type") or "").lower()
        status_hint = str(signal.get("status_hint") or "").lower()
        source_quality = str(signal.get("source_quality") or "").lower()
        evidence_text = " ".join(_string_list(signal.get("evidence")) + _string_list(signal.get("appserver_activity_evidence"))).lower()
        if (
            event_type in {"unknown", "appserver_quiet"}
            or status_hint in {"unknown", "notloaded", "not_loaded", "idle", "quiet", "complete", "completed"}
            or any(marker in source_quality for marker in ("unknown", "ignored", "quiet"))
            or (not signal.get("appserver_activity_evidence") and any(marker in evidence_text for marker in ("status=notloaded", "status=unknown", "status=idle", "status=complete", "status=completed")))
        ):
            return min(float(signal.get("confidence") or 0.0), 0.3)
        return float(base.get("codex_appserver_active", 0.95))
    if source == "codex_private_probe":
        if bool(signal.get("turn_scoped")):
            return float(base.get("private_probe_turn_scoped", 0.8))
        if bool(signal.get("thread_scoped")):
            return float(base.get("private_probe_thread_scoped", 0.7))
        if source_quality == "global_private_metadata":
            return float(base.get("private_probe_global_only", 0.3))
        return min(float(base.get("private_probe_global_only", 0.3)), float(signal.get("confidence") or 0.3))
    if source == "process_observer" or event_type.startswith("observed_"):
        return float(base.get("process_observer", 0.35))
    if source == "current_thread_watcher":
        return float(base.get("current_thread_watcher", 0.7))
    return float(signal.get("confidence") or 0.5)


def runtime_ttl_for_signal(signal: dict[str, Any], ttl_config: dict[str, float]) -> float:
    source = str(signal.get("source") or "")
    if source in ttl_config:
        return ttl_config[source]
    return float(ttl_config.get("process_observer", 5))


def runtime_candidate_id(signal: dict[str, Any]) -> tuple[str, str]:
    turn_id = str(signal.get("turn_id") or "")
    thread_id = str(signal.get("thread_id") or "")
    task_id = str(signal.get("task_id") or "")
    observation_id = str(signal.get("observation_id") or "")
    pid = signal.get("pid")
    if turn_id:
        return "codex_turn", f"turn:{turn_id}"
    if thread_id:
        source = str(signal.get("source") or "thread")
        return "appserver_thread" if source == "codex_appserver" else "current_thread", f"thread:{thread_id}"
    if task_id:
        return "codex_turn", f"task:{task_id}"
    if observation_id:
        return "process_observer", f"observation:{observation_id}"
    if pid is not None:
        return "process_observer", f"pid:{pid}"
    return "private_probe", "global:private_probe"


def consistency_score_for_candidate(sources: set[str], signals: list[dict[str, Any]], config: dict[str, Any]) -> float:
    scores = config.get("consistency_score", {}) if isinstance(config.get("consistency_score"), dict) else {}
    if "codex_hook" in sources and "codex_appserver" in sources:
        return float(scores.get("hook_and_appserver_agree", 1.0))
    if sources & {"explicit", "tasklight", "wrapper", "codex_hook", "codex_appserver"}:
        return float(scores.get("one_strong_source_fresh", 0.9))
    if sources == {"process_observer"}:
        return float(scores.get("process_only_max", 0.6))
    if sources == {"codex_private_probe"}:
        if all(not signal.get("thread_id") and not signal.get("turn_id") for signal in signals):
            return float(scores.get("private_global_only_max", 0.3))
        return 0.7
    if sources == {"current_thread_watcher"}:
        return 0.6
    return 0.7


def runtime_scope(runtime_score: float, config: dict[str, Any]) -> str:
    thresholds = config.get("scope_thresholds", {}) if isinstance(config.get("scope_thresholds"), dict) else {}
    if runtime_score >= float(thresholds.get("active_execution_min", 0.85)):
        return "active_execution"
    if runtime_score >= float(thresholds.get("observed_active_high_confidence_min", 0.55)):
        return "observed_active_high_confidence"
    if runtime_score >= float(thresholds.get("observed_only_min", 0.35)):
        return "observed_only"
    return "ignored"


def build_runtime_candidates(
    bus_signals: list[dict[str, Any]],
    *,
    now_ts: float,
    confidence_config: dict[str, Any],
    ttl_config: dict[str, float],
    current_thread_id: str | None,
    active_task_thread_ids: set[str],
) -> list[dict[str, Any]]:
    buckets: dict[str, list[dict[str, Any]]] = {}
    for signal in bus_signals:
        source = str(signal.get("source") or "")
        event_type = str(signal.get("event_type") or "")
        status_hint = str(signal.get("status_hint") or "")
        if source not in {"explicit", "tasklight", "wrapper", "codex_hook", "codex_appserver", "codex_private_probe", "process_observer", "current_thread_watcher"}:
            continue
        if event_type in DONE_SIGNAL_EVENTS | VERIFIED_SIGNAL_EVENTS | RELEASE_SIGNAL_EVENTS:
            continue
        if status_hint in {"done_unverified", "done_verified", "cancelled"}:
            continue
        kind, candidate_id = runtime_candidate_id(signal)
        buckets.setdefault(candidate_id, []).append(signal)

    candidates: list[dict[str, Any]] = []
    for candidate_id, signals in buckets.items():
        signals.sort(key=lambda item: parse_ts(item.get("occurred_at")) or 0)
        latest = signals[-1]
        sources = {str(signal.get("source") or "unknown") for signal in signals}
        event_types = {str(signal.get("event_type") or "") for signal in signals}
        ages = [signal_age(signal, now_ts) for signal in signals]
        fresh_scores = [
            freshness_score(age, runtime_ttl_for_signal(signal, ttl_config))
            for signal, age in zip(signals, ages)
        ]
        best_index = max(range(len(signals)), key=lambda index: (
            fresh_scores[index],
            base_confidence_for_signal(signals[index], confidence_config),
            parse_ts(signals[index].get("occurred_at")) or 0,
        ))
        best_signal = signals[best_index]
        kind, _candidate_id = runtime_candidate_id(best_signal)
        base = base_confidence_for_signal(best_signal, confidence_config)
        freshness = fresh_scores[best_index]
        identity = signal_identity_score(best_signal, confidence_config)
        consistency = consistency_score_for_candidate(sources, signals, confidence_config)
        source_quality = str(best_signal.get("source_quality") or "")
        best_age = ages[best_index]
        appserver_results = [
            is_appserver_active_like_signal(signal, age=signal_age(signal, now_ts), ttl=runtime_ttl_for_signal(signal, ttl_config))
            for signal in signals
            if str(signal.get("source") or "") == "codex_appserver"
        ]
        appserver_active_results = [result for result in appserver_results if result[0]]
        appserver_ignored_reasons = [result[2] for result in appserver_results if result[2]]
        appserver_evidence = sorted({item for result in appserver_results for item in result[3]})
        if sources == {"process_observer"}:
            consistency = min(consistency, 0.6)
        if sources == {"codex_private_probe"} and source_quality == "global_private_metadata":
            consistency = min(consistency, 0.3)
            identity = min(identity, 0.2)
        if sources == {"current_thread_watcher"}:
            consistency = min(consistency, 0.6)
        if best_signal.get("thread_id") and current_thread_id and best_signal.get("thread_id") == current_thread_id and "codex_appserver" in sources:
            consistency = min(consistency, 0.3)
        if best_signal.get("thread_id") and str(best_signal.get("thread_id")) in active_task_thread_ids and "codex_appserver" in sources:
            consistency = min(consistency, 0.5)
        score = round(base * freshness * identity * consistency, 4)
        scope = runtime_scope(score, confidence_config)
        if sources == {"process_observer"} and scope in {"active_execution", "observed_active_high_confidence"}:
            scope = "observed_only"
        if sources == {"codex_private_probe"} and source_quality == "global_private_metadata":
            scope = "ignored" if score < 0.35 else "observed_only"
        if sources == {"current_thread_watcher"} and scope == "active_execution":
            scope = "observed_active_high_confidence"
        if "codex_appserver" in sources and scope == "active_execution" and not best_signal.get("turn_id"):
            scope = "observed_active_high_confidence"
        if "codex_appserver" in sources and not appserver_active_results and sources == {"codex_appserver"}:
            scope = "ignored"
            score = min(score, 0.34)

        why_active = None
        why_ignored = None
        if scope in {"active_execution", "observed_active_high_confidence"}:
            if appserver_active_results:
                why_active = appserver_active_results[0][1]
            elif sources == {"codex_hook"}:
                why_active = "fresh_hook_turn_signal"
            elif sources & {"explicit", "tasklight", "wrapper"}:
                why_active = "fresh_managed_task_signal"
            else:
                why_active = "runtime_score_threshold_met"
        elif "codex_appserver" in sources and not appserver_active_results:
            why_ignored = appserver_ignored_reasons[0] if appserver_ignored_reasons else "missing_active_like_evidence"
        elif scope == "ignored":
            why_ignored = "runtime_score_below_threshold"

        candidates.append(
            {
                "candidate_id": candidate_id,
                "kind": kind,
                "task_id": best_signal.get("task_id"),
                "thread_id": best_signal.get("thread_id"),
                "turn_id": best_signal.get("turn_id"),
                "pid": best_signal.get("pid"),
                "source_set": sorted(sources),
                "last_signal_at": best_signal.get("occurred_at"),
                "last_event_type": best_signal.get("event_type"),
                "age_sec": None if best_age is None else round(best_age, 2),
                "base_confidence": round(base, 3),
                "freshness_score": round(freshness, 3),
                "identity_score": round(identity, 3),
                "consistency_score": round(consistency, 3),
                "runtime_score": score,
                "display_scope": scope,
                "state_cause": f"{best_signal.get('source')}:{best_signal.get('event_type')}",
                "why_active": why_active,
                "why_ignored": why_ignored,
                "appserver_activity_evidence": appserver_evidence,
                "reason": best_signal.get("reason"),
                "message": best_signal.get("message"),
            }
        )
    candidates.sort(key=lambda item: (float(item.get("runtime_score") or 0), str(item.get("last_signal_at") or "")), reverse=True)
    return candidates


def project_once(root: Path, args: argparse.Namespace) -> dict[str, Any]:
    now_ts = time.time()
    generated_at = now_iso()
    hook_active_ttl = float(args.hook_active_ttl)
    current_thread_active_ttl = current_thread_active_display_ttl_seconds()
    completed_idle_seconds = float(args.completed_idle_seconds)
    hook_turn_lease_seconds = float(args.hook_turn_lease_seconds)
    observed_ttl = float(args.observed_active_ttl)
    verification_ttl = float(args.verification_ttl_seconds)
    done_visible_hours = float(args.done_visible_hours)

    bus_signals, signal_bus_status = load_signal_bus(root, int(args.normalized_signal_limit))
    signal_bus_has_records = signal_bus_status == "readable" and bool(bus_signals)
    state = load_json(root / "state.json", {})
    tasks, invalid_tasks = load_tasks(root)
    by_task, by_turn, by_identity, bindings = load_bindings(root)
    thread_by_task, _thread_by_thread, thread_bindings = load_thread_bindings(root)
    tasks = synthesize_tasks_from_signals(tasks, bindings_by_turn=by_turn, bus_signals=bus_signals)
    observation_catalog = load_observation_catalog(root)
    observations, observation_signals, observed_false_positive_count = project_observations(
        observation_catalog,
        bus_signals,
        now_ts,
        observed_ttl,
        signal_bus_has_records,
    )
    appserver_thread_signals = [signal for signal in bus_signals if str(signal.get("source") or "") == "codex_appserver"]
    appserver_thread_health = load_json(appserver_thread_watcher_health_path(root), {})
    quota, quota_diagnostics = project_quota_state(root, now_ts)
    if appserver_thread_signals:
        appserver_thread_signal_status = "bus"
    elif isinstance(appserver_thread_health, dict) and appserver_thread_health.get("status"):
        appserver_thread_signal_status = f"watcher_{appserver_thread_health.get('status')}"
    else:
        appserver_thread_signal_status = "none"
    hook_health = load_json(root / "hook_bridge_health.json", {})
    ui_clients = load_ui_clients(root)
    signals_by_task: dict[str, list[dict[str, Any]]] = {}
    signals_by_turn: dict[str, list[dict[str, Any]]] = {}
    signals_by_thread: dict[str, list[dict[str, Any]]] = {}
    for signal in bus_signals:
        task_id = str(signal.get("task_id") or "")
        turn_id = str(signal.get("turn_id") or "")
        thread_id = str(signal.get("thread_id") or "")
        if task_id:
            signals_by_task.setdefault(task_id, []).append(signal)
        if turn_id:
            signals_by_turn.setdefault(turn_id, []).append(signal)
        if thread_id:
            signals_by_thread.setdefault(thread_id, []).append(signal)

    projected_tasks: list[dict[str, Any]] = []
    signals: list[dict[str, Any]] = []
    for task in tasks:
        task_id = str(task.get("task_id") or "")
        projected, signal = classify_task(
            task,
            by_task.get(task_id),
            thread_by_task.get(task_id),
            now_ts=now_ts,
            hook_active_ttl=hook_active_ttl,
            current_thread_active_ttl=current_thread_active_ttl,
            completed_idle_seconds=completed_idle_seconds,
            hook_turn_lease_seconds=hook_turn_lease_seconds,
            verification_ttl=verification_ttl,
            done_visible_hours=done_visible_hours,
            signals_by_task=signals_by_task,
            signals_by_turn=signals_by_turn,
            signals_by_thread=signals_by_thread,
            signal_bus_has_records=signal_bus_has_records,
        )
        projected_tasks.append(projected)
        signals.append(signal)
    for invalid in invalid_tasks:
        projected_tasks.append(invalid)
        signals.append(
            make_signal(
                "tasklight",
                "invalid_json",
                identity={"task_id": invalid.get("task_id"), "turn_id": None, "thread_id": None, "pid": None},
                confidence=0.40,
                occurred_at=generated_at,
                status_hint="invalid_json",
            )
        )
    signals.extend(observation_signals)
    signals.sort(key=lambda item: str(item.get("occurred_at") or ""))
    for index, signal in enumerate(signals, start=1):
        signal["ingested_seq"] = index

    current_thread_signal = latest_signal_by_source(bus_signals, "current_thread_watcher")
    current_thread_binding = latest_binding(thread_bindings)
    current_thread_id = str(
        (current_thread_binding or {}).get("thread_id")
        or (current_thread_signal or {}).get("thread_id")
        or os.environ.get("CODEX_THREAD_ID")
        or ""
    ) or None
    active_task_thread_ids = {
        str(binding.get("thread_id"))
        for binding in thread_bindings
        if binding.get("status") == "active" and binding.get("thread_id")
    }
    appserver_observations, appserver_live_thread_count, latest_appserver_thread_age = project_appserver_thread_observations(
        appserver_thread_signals,
        now_ts=now_ts,
        active_ttl=appserver_thread_active_ttl_seconds(),
        current_thread_id=current_thread_id,
        active_task_thread_ids=active_task_thread_ids,
    )
    observations.extend(appserver_observations)
    confidence_config = runtime_confidence_config()
    ttl_config = runtime_ttl_config()
    runtime_candidates = build_runtime_candidates(
        bus_signals,
        now_ts=now_ts,
        confidence_config=confidence_config,
        ttl_config=ttl_config,
        current_thread_id=current_thread_id,
        active_task_thread_ids=active_task_thread_ids,
    )
    latest_appserver_candidate = next(
        (candidate for candidate in runtime_candidates if "codex_appserver" in set(candidate.get("source_set") or [])),
        None,
    )
    weak_observed_count = sum(1 for candidate in runtime_candidates if candidate.get("display_scope") == "observed_only")

    counts = build_counts(projected_tasks, observations)
    global_status, display_title, confidence, reasons = global_from_projection(projected_tasks, counts, runtime_candidates)
    old_global = state.get("global_status") if isinstance(state, dict) else None
    old_counts = state.get("counts") if isinstance(state, dict) and isinstance(state.get("counts"), dict) else {}
    running_mismatch = bool(
        old_global in {"running", "blocked"} and global_status not in {"running", "blocked"}
    )
    if old_counts and int(old_counts.get("running") or 0) != counts["running"]:
        running_mismatch = True
    client = latest_ui_client(ui_clients)
    latest_private_probe_signal = latest_signal_by_source(bus_signals, "codex_private_probe")
    latest_turn_binding = latest_binding(bindings)
    latest_turn_binding_age = age_seconds(
        (latest_turn_binding or {}).get("last_signal_at") or (latest_turn_binding or {}).get("updated_at"),
        now_ts,
    )
    current_thread_binding_age = age_seconds(
        (current_thread_binding or {}).get("updated_at") or (current_thread_binding or {}).get("created_at"),
        now_ts,
    )
    current_thread_binding_fresh = (
        current_thread_binding is not None
        and str(current_thread_binding.get("status") or "") == "active"
        and current_thread_binding_age is not None
        and current_thread_binding_age <= current_thread_active_ttl
    )

    projected_tasks.sort(
        key=lambda task: (
            {"open_blocker": 0, "active_execution": 1, "pending_verify": 2, "recent_done": 3, "stale_blocker": 4, "resolved_blocker": 5, "invalid": 6, "history": 7, "released": 8}.get(str(task.get("display_scope")), 9),
            str(task.get("updated_at") or ""),
        ),
        reverse=False,
    )

    signal_ages = [
        age_seconds(signal.get("occurred_at"), now_ts)
        for signal in bus_signals
        if age_seconds(signal.get("occurred_at"), now_ts) is not None
    ]
    bus_source_counts = signal_source_counts(bus_signals)

    payload = {
        "schema_version": SCHEMA_VERSION,
        "source": "state_projector",
        "projector_version": PROJECTOR_VERSION,
        "projector_pid": os.getpid(),
        "projector_executable_path": str(Path(sys.argv[0]).resolve()),
        "projector_code_hash": projector_code_hash(),
        "projector_launch_label": PROJECTOR_LAUNCH_LABEL,
        "projector_instance_id": PROJECTOR_INSTANCE_ID,
        "projector_generated_at": generated_at,
        "global_status": global_status,
        "lamp_status": global_status,
        "global_display_title": display_title,
        "state_confidence": round(confidence, 2),
        "counts": counts,
        "tasks": projected_tasks,
        "observations": observations,
        "runtime_candidates": runtime_candidates,
        "quota": quota,
        "diagnostics": {
            "writer_status": "ok",
            "hook_bridge_status": hook_health.get("status", "unknown") if isinstance(hook_health, dict) else "unknown",
            "signal_bus_status": signal_bus_status,
            "signal_bus_record_count": len(bus_signals),
            "signal_bus_source_counts": bus_source_counts,
            "latest_signal_age_sec": None if not signal_ages else round(min(signal_ages), 2),
            "latest_hook_signal_age_sec": latest_signal_age_for_source(bus_signals, "codex_hook", now_ts),
            "latest_hook_bridge_signal_age_sec": latest_signal_age_for_source(bus_signals, "hook_bridge", now_ts),
            "latest_process_observer_signal_age_sec": latest_signal_age_for_source(bus_signals, "process_observer", now_ts),
            "latest_private_probe_signal_age_sec": latest_signal_age_for_source(bus_signals, "codex_private_probe", now_ts),
            "active_turn_bindings": int((hook_health or {}).get("active_turn_bindings") or sum(1 for binding in bindings if binding.get("status") == "active")),
            "latest_active_turn_age_sec": latest_active_turn_age(bindings, now_ts),
            "latest_observed_age_sec": latest_observed_age(observations),
            "latest_private_probe_status": (latest_private_probe_signal or {}).get("status_hint") or (latest_private_probe_signal or {}).get("event_type"),
            "latest_private_probe_quality": (latest_private_probe_signal or {}).get("source_quality"),
            "latest_private_probe_confidence": (latest_private_probe_signal or {}).get("confidence"),
            "appserver_thread_signal_status": appserver_thread_signal_status,
            "appserver_live_thread_count": appserver_live_thread_count,
            "appserver_active_count": counts.get("appserver_active", 0),
            "process_observed_count": counts.get("process_observed", 0),
            "weak_observed_count": weak_observed_count,
            "latest_appserver_thread_age_sec": latest_appserver_thread_age,
            "latest_appserver_state_cause": (latest_appserver_candidate or {}).get("state_cause"),
            "appserver_thread_watcher_status": (appserver_thread_health or {}).get("status"),
            "runtime_candidate_count": len(runtime_candidates),
            "top_runtime_candidates": runtime_candidates[:5],
            "current_thread_binding_status": (current_thread_binding or {}).get("status"),
            "current_thread_binding_fresh": current_thread_binding_fresh,
            "latest_current_thread_binding_age_sec": None if current_thread_binding_age is None else round(current_thread_binding_age, 2),
            "latest_current_thread_signal_age_sec": latest_current_thread_signal_age(bus_signals, now_ts),
            "current_thread_task_identity": (current_thread_binding or {}).get("task_identity"),
            "current_thread_signal_source": (current_thread_signal or {}).get("source"),
            "current_thread_signal_quality": (current_thread_signal or {}).get("source_quality"),
            "current_thread_signal_confidence": (current_thread_signal or {}).get("confidence"),
            "current_thread_signal_status": (current_thread_signal or {}).get("status_hint") or (current_thread_signal or {}).get("event_type"),
            "current_thread_fusion_decision": (current_thread_binding or {}).get("last_fusion_decision"),
            "latest_turn_binding_status": (latest_turn_binding or {}).get("status"),
            "latest_turn_binding_age_sec": None if latest_turn_binding_age is None else round(latest_turn_binding_age, 2),
            "latest_turn_binding_turn_id": (latest_turn_binding or {}).get("turn_id"),
            "latest_turn_binding_task_id": (latest_turn_binding or {}).get("task_id"),
            "latest_turn_binding_canonical_identity": binding_canonical_identity(latest_turn_binding),
            "latest_turn_binding_aliases": list((latest_turn_binding or {}).get("aliases") or []),
            "latest_turn_signal_event": (latest_turn_binding or {}).get("last_signal_event"),
            "latest_bridge_decision": (latest_turn_binding or {}).get("last_bridge_decision"),
            "running_mismatch_warning": running_mismatch,
            "state_dir": str(root),
            "app_bundle_path": (client or {}).get("bundle_path"),
            "build_id": (client or {}).get("build_id"),
            "projector_reason": reasons,
            "observed_false_positive_count": observed_false_positive_count,
            "active_thread_bindings": sum(1 for binding in thread_bindings if binding.get("status") == "active"),
            "binding_identity_count": len(by_identity),
            **quota_diagnostics,
        },
    }
    atomic_write_json(output_path(root), payload)
    return payload


def write_health(path: Path, status: str, payload: dict[str, Any] | None, error: str | None) -> None:
    health = {
        "schema_version": SCHEMA_VERSION,
        "status": status,
        "projector_version": PROJECTOR_VERSION,
        "projector_pid": os.getpid(),
        "projector_code_hash": projector_code_hash(),
        "projector_launch_label": PROJECTOR_LAUNCH_LABEL,
        "last_run_at": now_iso(),
        "last_error": error,
        "ui_state_path": str(output_path(state_dir())),
        "global_status": (payload or {}).get("global_status"),
        "state_confidence": (payload or {}).get("state_confidence"),
        "updated_at": now_iso(),
    }
    atomic_write_json(path, health)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Project 66TaskLight inputs into ui_state.json")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--once", action="store_true")
    mode.add_argument("--watch", action="store_true")
    parser.add_argument("--poll-seconds", type=float, default=float(os.environ.get("TASKLIGHT_STATE_PROJECTOR_POLL_SECONDS", "1")))
    parser.add_argument("--hook-active-ttl", type=float, default=float(os.environ.get("TASKLIGHT_HOOK_ACTIVE_DISPLAY_TTL_SECONDS", "12")))
    parser.add_argument("--completed-idle-seconds", type=float, default=float(os.environ.get("TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS", "20")))
    parser.add_argument("--hook-turn-lease-seconds", type=float, default=float(os.environ.get("TASKLIGHT_HOOK_TURN_LEASE_SECONDS", "60")))
    parser.add_argument("--observed-active-ttl", type=float, default=float(os.environ.get("TASKLIGHT_OBSERVED_ACTIVE_TTL_SECONDS", "8")))
    parser.add_argument("--verification-ttl-seconds", type=float, default=verification_ttl_seconds())
    parser.add_argument("--done-visible-hours", type=float, default=float(os.environ.get("TASKLIGHT_DONE_VISIBLE_HOURS", "24")))
    parser.add_argument("--normalized-signal-limit", type=int, default=int(os.environ.get("TASKLIGHT_NORMALIZED_SIGNAL_LIMIT", "500")))
    return parser


def main() -> int:
    args = build_parser().parse_args()
    root = state_dir()
    root.mkdir(parents=True, exist_ok=True)
    health = health_path(root)
    if args.once:
        try:
            payload = project_once(root, args)
            write_health(health, "ok", payload, None)
            print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))
            return 0
        except Exception as exc:
            write_health(health, "error", None, str(exc))
            raise

    while True:
        try:
            payload = project_once(root, args)
            write_health(health, "ok", payload, None)
        except Exception as exc:
            write_health(health, "error", None, str(exc))
        time.sleep(max(0.2, float(args.poll_seconds)))


if __name__ == "__main__":
    raise SystemExit(main())
