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
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "0.1"
DEFAULT_STATE_DIR = Path.home() / ".66tasklight"
DISPLAY_SCOPES = {
    "active_execution",
    "open_blocker",
    "pending_verify",
    "recent_done",
    "history",
    "released",
    "invalid",
}
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


def load_bindings(root: Path) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]], list[dict[str, Any]]]:
    bindings_dir = root / "turn_bindings"
    by_task: dict[str, dict[str, Any]] = {}
    by_turn: dict[str, dict[str, Any]] = {}
    all_bindings: list[dict[str, Any]] = []
    if not bindings_dir.exists():
        return by_task, by_turn, all_bindings
    for path in sorted(bindings_dir.glob("*.json")):
        payload = load_json(path, {})
        if not isinstance(payload, dict):
            continue
        payload = dict(payload)
        payload["file_path"] = str(path)
        all_bindings.append(payload)
        task_id = payload.get("task_id")
        turn_id = payload.get("turn_id")
        if task_id:
            by_task[str(task_id)] = payload
        if turn_id:
            by_turn[str(turn_id)] = payload
    return by_task, by_turn, all_bindings


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


def binding_is_fresh(binding: dict[str, Any] | None, now_ts: float, ttl: float) -> bool:
    if not binding or binding.get("status") != "active":
        return False
    last_age = age_seconds(binding.get("last_signal_at") or binding.get("updated_at"), now_ts)
    return last_age is not None and last_age <= ttl


def classify_task(
    task: dict[str, Any],
    binding: dict[str, Any] | None,
    *,
    now_ts: float,
    hook_active_ttl: float,
    completed_idle_seconds: float,
    hook_turn_lease_seconds: float,
    done_visible_hours: float,
) -> tuple[dict[str, Any], dict[str, Any]]:
    raw_status = str(task.get("raw_status") or task.get("status") or task.get("effective_status") or "idle")
    effective_status = str(task.get("effective_status") or task.get("status") or raw_status)
    source = "codex_hook" if is_hook_projected_task(task, binding) else str(task.get("source") or "tasklight")
    binding_age = age_seconds((binding or {}).get("last_signal_at") or (binding or {}).get("updated_at"), now_ts)
    last_signal_event = (binding or {}).get("last_signal_event")
    display_scope = "history"
    state_cause = f"task:{effective_status}"
    fresh = False
    confidence = 0.80

    if source == "codex_hook" and raw_status in {"running", "queued", "stale", "blocked"}:
        confidence = 0.95
        if binding_is_fresh(binding, now_ts, hook_active_ttl):
            fresh = True
            if last_signal_event == "item_completed" and binding_age is not None and binding_age > completed_idle_seconds:
                display_scope = "released"
                state_cause = "hook:item_completed_idle_timeout"
            elif raw_status == "blocked" or effective_status == "blocked":
                blocker_age = binding_age if binding_age is not None else hook_turn_lease_seconds + 1
                if blocker_age <= hook_turn_lease_seconds:
                    display_scope = "open_blocker"
                    state_cause = "hook:blocker_fresh"
                else:
                    display_scope = "released"
                    state_cause = "hook:blocker_stale"
            else:
                display_scope = "active_execution"
                state_cause = f"hook:{last_signal_event or 'active'}"
        else:
            display_scope = "released"
            state_cause = "hook:not_fresh"
    elif effective_status in {"blocked", "stale"}:
        display_scope = "open_blocker"
        state_cause = f"task:{effective_status}"
        confidence = 1.0 if raw_status == "blocked" else 0.90
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
        "turn_id": (binding or {}).get("turn_id"),
        "source": source,
        "raw_status": raw_status,
        "effective_status": effective_status,
        "display_scope": display_scope if display_scope in DISPLAY_SCOPES else "history",
        "last_signal_age_sec": None if binding_age is None else round(binding_age, 2),
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
    signal = make_signal(
        source,
        state_cause,
        identity={"task_id": task_id, "turn_id": projected["turn_id"], "thread_id": (binding or {}).get("thread_id"), "pid": None},
        confidence=confidence,
        occurred_at=(binding or {}).get("last_signal_at") or task_timestamp(task),
        status_hint=projected["effective_status"],
    )
    return projected, signal


def observation_allowed(record: dict[str, Any]) -> bool:
    command = str(record.get("command") or record.get("command_short") or "").lower()
    return not any(snippet in command for snippet in OBSERVED_EXCLUDE_SNIPPETS)


def project_observations(root: Path, now_ts: float, observed_ttl: float) -> tuple[list[dict[str, Any]], list[dict[str, Any]], int]:
    state = load_json(root / "observations_state.json", {})
    records = state.get("observations") if isinstance(state, dict) else []
    if not isinstance(records, list):
        records = []
    projected: list[dict[str, Any]] = []
    signals: list[dict[str, Any]] = []
    false_positive_count = 0
    for record in records:
        if not isinstance(record, dict):
            continue
        seen_age = age_seconds(record.get("last_seen_at") or record.get("detected_at"), now_ts)
        fresh = seen_age is not None and seen_age <= observed_ttl
        confidence = float(record.get("confidence") or 0.0)
        allowed = observation_allowed(record)
        if not allowed:
            false_positive_count += 1
        status = str(record.get("status") or "observed_quiet")
        display_scope = "active_execution" if status == "observed_active" and fresh and confidence >= 0.70 and allowed else "history"
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


def build_counts(tasks: list[dict[str, Any]], observations: list[dict[str, Any]]) -> dict[str, int]:
    counts = {
        "blocked": 0,
        "stale": 0,
        "running": 0,
        "queued": 0,
        "pending_verify_count": 0,
        "done_verified_visible": 0,
        "observed_active": 0,
        "managed_active": 0,
    }
    for task in tasks:
        scope = task.get("display_scope")
        status = task.get("effective_status")
        if scope == "open_blocker":
            if status == "stale":
                counts["stale"] += 1
            else:
                counts["blocked"] += 1
            counts["managed_active"] += 1
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
    counts["observed_active"] = sum(1 for item in observations if item.get("display_scope") == "active_execution")
    return counts


def global_from_projection(tasks: list[dict[str, Any]], observations: list[dict[str, Any]], counts: dict[str, int]) -> tuple[str, str, float, list[str]]:
    reasons: list[str] = []
    open_blockers = [task for task in tasks if task.get("display_scope") == "open_blocker"]
    active_tasks = [task for task in tasks if task.get("display_scope") == "active_execution"]
    pending_tasks = [task for task in tasks if task.get("display_scope") == "pending_verify"]
    active_observed = [item for item in observations if item.get("display_scope") == "active_execution" and float(item.get("confidence") or 0) >= 0.70]
    if open_blockers:
        reasons.append("open_blocker")
        return "blocked", "BLOCKED", max(float(task.get("confidence") or 0.9) for task in open_blockers), reasons
    if active_tasks:
        reasons.append("active_execution")
        return "running", "RUNNING", max(float(task.get("confidence") or 0.95) for task in active_tasks), reasons
    if active_observed:
        reasons.append("observed_active")
        return "running", "RUNNING", max(float(item.get("confidence") or 0.70) for item in active_observed), reasons
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


def latest_ui_client(clients: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not clients:
        return None
    return sorted(clients, key=lambda item: parse_ts(item.get("updated_at") or item.get("started_at")) or 0, reverse=True)[0]


def project_once(root: Path, args: argparse.Namespace) -> dict[str, Any]:
    now_ts = time.time()
    generated_at = now_iso()
    hook_active_ttl = float(args.hook_active_ttl)
    completed_idle_seconds = float(args.completed_idle_seconds)
    hook_turn_lease_seconds = float(args.hook_turn_lease_seconds)
    observed_ttl = float(args.observed_active_ttl)
    done_visible_hours = float(args.done_visible_hours)

    state = load_json(root / "state.json", {})
    tasks, invalid_tasks = load_tasks(root)
    by_task, _by_turn, bindings = load_bindings(root)
    observations, observation_signals, observed_false_positive_count = project_observations(root, now_ts, observed_ttl)
    hook_health = load_json(root / "hook_bridge_health.json", {})
    ui_clients = load_ui_clients(root)

    projected_tasks: list[dict[str, Any]] = []
    signals: list[dict[str, Any]] = []
    for task in tasks:
        task_id = str(task.get("task_id") or "")
        projected, signal = classify_task(
            task,
            by_task.get(task_id),
            now_ts=now_ts,
            hook_active_ttl=hook_active_ttl,
            completed_idle_seconds=completed_idle_seconds,
            hook_turn_lease_seconds=hook_turn_lease_seconds,
            done_visible_hours=done_visible_hours,
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

    counts = build_counts(projected_tasks, observations)
    global_status, display_title, confidence, reasons = global_from_projection(projected_tasks, observations, counts)
    old_global = state.get("global_status") if isinstance(state, dict) else None
    old_counts = state.get("counts") if isinstance(state, dict) and isinstance(state.get("counts"), dict) else {}
    running_mismatch = bool(
        old_global in {"running", "blocked"} and global_status not in {"running", "blocked"}
    )
    if old_counts and int(old_counts.get("running") or 0) != counts["running"]:
        running_mismatch = True
    client = latest_ui_client(ui_clients)

    projected_tasks.sort(
        key=lambda task: (
            {"open_blocker": 0, "active_execution": 1, "pending_verify": 2, "recent_done": 3, "invalid": 4, "history": 5, "released": 6}.get(str(task.get("display_scope")), 9),
            str(task.get("updated_at") or ""),
        ),
        reverse=False,
    )

    payload = {
        "schema_version": SCHEMA_VERSION,
        "source": "state_projector",
        "projector_generated_at": generated_at,
        "global_status": global_status,
        "lamp_status": global_status,
        "global_display_title": display_title,
        "state_confidence": round(confidence, 2),
        "counts": counts,
        "tasks": projected_tasks,
        "observations": observations,
        "diagnostics": {
            "hook_bridge_status": hook_health.get("status", "unknown") if isinstance(hook_health, dict) else "unknown",
            "active_turn_bindings": int((hook_health or {}).get("active_turn_bindings") or sum(1 for binding in bindings if binding.get("status") == "active")),
            "latest_active_turn_age_sec": latest_active_turn_age(bindings, now_ts),
            "latest_observed_age_sec": latest_observed_age(observations),
            "running_mismatch_warning": running_mismatch,
            "state_dir": str(root),
            "app_bundle_path": (client or {}).get("bundle_path"),
            "build_id": (client or {}).get("build_id"),
            "projector_reason": reasons,
            "observed_false_positive_count": observed_false_positive_count,
        },
    }
    write_jsonl(normalized_signals_path(root), signals, int(args.normalized_signal_limit))
    atomic_write_json(output_path(root), payload)
    return payload


def write_health(path: Path, status: str, payload: dict[str, Any] | None, error: str | None) -> None:
    health = {
        "schema_version": SCHEMA_VERSION,
        "status": status,
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
