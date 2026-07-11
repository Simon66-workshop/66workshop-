#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTOR="$ROOT_DIR/script/state_projector.py"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-runtime-arbiter-XXXXXX")"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

export ROOT_DIR
export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_UI_STATE_PATH="$STATE_DIR/ui_state.json"
export TASKLIGHT_STATE_PROJECTOR_HEALTH_PATH="$STATE_DIR/state_projector_health.json"
export TASKLIGHT_NORMALIZED_SIGNALS_PATH="$STATE_DIR/normalized_signals.jsonl"
export TASKLIGHT_SIGNAL_BUS_MAX_AGE_SECONDS=9999999999
export TASKLIGHT_HOOK_ACTIVE_DISPLAY_TTL_SECONDS=12
export TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS=20
export TASKLIGHT_HOOK_TURN_LEASE_SECONDS=60
export TASKLIGHT_OBSERVED_ACTIVE_TTL_SECONDS=8
export TASKLIGHT_DONE_VISIBLE_HOURS=24
export TASKLIGHT_STATE_PROJECTOR_PROCESS_COUNT_OVERRIDE=1

mkdir -p "$STATE_DIR/tasks" "$STATE_DIR/turn_bindings" "$STATE_DIR/thread_bindings"

python3 - "$PROJECTOR" "$ROOT_DIR/script/check_state_projector.sh" <<'PY'
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

projector = Path(sys.argv[1])
check_script = Path(sys.argv[2])
state_dir = Path(os.environ["TASKLIGHT_STATE_DIR"])
signals_path = Path(os.environ["TASKLIGHT_NORMALIZED_SIGNALS_PATH"])
ui_state_path = Path(os.environ["TASKLIGHT_UI_STATE_PATH"])


def stamp(age=0):
    return (datetime.now(timezone.utc) - timedelta(seconds=age)).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def reset():
    for child in state_dir.iterdir():
        if child.name in {"tasks", "turn_bindings", "thread_bindings"}:
            shutil.rmtree(child)
        elif child.is_dir():
            # New sidecar directories (for example provider state) are allowed
            # in a state root and must not make an arbiter fixture reset crash.
            shutil.rmtree(child)
        else:
            child.unlink(missing_ok=True)
    (state_dir / "tasks").mkdir(exist_ok=True)
    (state_dir / "turn_bindings").mkdir(exist_ok=True)
    (state_dir / "thread_bindings").mkdir(exist_ok=True)


def write_signals(records):
    signals_path.parent.mkdir(parents=True, exist_ok=True)
    with signals_path.open("w", encoding="utf-8") as handle:
        for record in records:
            payload = {
                "confidence": 0.95,
                "thread_scoped": bool(record.get("thread_id")),
                "turn_scoped": bool(record.get("turn_id")),
                "source_quality": "smoke",
                "evidence": ["m3.3-smoke"],
                "conflicts": [],
            }
            payload.update(record)
            payload.setdefault("occurred_at", stamp())
            handle.write(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n")


def write_task(task_id, status, **extra):
    now = stamp()
    payload = {
        "schema_version": 3,
        "task_id": task_id,
        "short_task_id": task_id[-8:],
        "title": extra.pop("title", task_id),
        "slug": task_id,
        "status": status,
        "raw_status": status,
        "effective_status": status,
        "phase": "smoke",
        "progress": 0.5,
        "created_at": now,
        "started_at": now,
        "updated_at": now,
        "heartbeat_at": now,
        "ttl_seconds": 300,
    }
    payload.update(extra)
    (state_dir / "tasks" / f"{task_id}.json").write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")


def write_binding(turn_id, task_id, *, age=1, status="active", event="item_started", thread_id=None):
    when = stamp(age)
    payload = {
        "schema_version": "0.1",
        "source_key": f"hook:unknown:{turn_id}",
        "canonical_identity": f"turn:{turn_id}",
        "aliases": [],
        "task_id": task_id,
        "turn_id": turn_id,
        "thread_id": thread_id,
        "session_id": None,
        "title": f"Codex turn {turn_id[:8]}",
        "cwd": "/tmp/tasklight-runtime-arbiter",
        "status": status,
        "phase": event,
        "last_signal_event": event,
        "last_signal_at": when,
        "created_at": when,
        "updated_at": when,
        "signal_count": 1,
    }
    (state_dir / "turn_bindings" / f"hook_unknown_{turn_id}.json").write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")


def run_projector():
    subprocess.check_call(["python3", str(projector), "--once"], stdout=subprocess.DEVNULL)
    return json.loads(ui_state_path.read_text(encoding="utf-8"))


def assert_case(condition, payload, label):
    if not condition:
        raise AssertionError(f"{label}\n{json.dumps(payload, indent=2, sort_keys=True)}")


# 1. fresh hook turn -> RUNNING
reset()
write_task("task-hook-fresh", "running")
write_binding("turn-hook-fresh", "task-hook-fresh")
write_signals([{"signal_id": "sig-hook-fresh", "source": "codex_hook", "event_type": "item_started", "task_id": "task-hook-fresh", "turn_id": "turn-hook-fresh"}])
p = run_projector()
assert_case(p["global_status"] == "running" and any(c["display_scope"] == "active_execution" for c in p["runtime_candidates"]), p, "fresh hook turn")

# 2. fresh appserver active thread without managed task -> RUNNING
reset()
write_signals([{"signal_id": "sig-appserver", "source": "codex_appserver", "event_type": "turn_started", "thread_id": "thread-appserver-m33"}])
p = run_projector()
assert_case(p["global_status"] == "running" and p["counts"]["appserver_active"] == 1, p, "fresh appserver active")

# 2b. fresh appserver notLoaded/unknown thread exists -> not RUNNING
reset()
write_signals([{
    "signal_id": "sig-appserver-unknown",
    "source": "codex_appserver",
    "event_type": "unknown",
    "thread_id": "thread-appserver-unknown",
    "source_quality": "codex_appserver_thread_list_ignored",
    "status_hint": "notLoaded",
    "confidence": 0,
    "evidence": ["thread/list:status=notLoaded"],
}])
p = run_projector()
candidate = p["runtime_candidates"][0]
assert_case(
    p["global_status"] == "idle"
    and candidate["display_scope"] == "ignored"
    and candidate.get("why_ignored"),
    p,
    "fresh appserver notLoaded ignored",
)

# 2c. stale appserver active thread-list evidence -> not RUNNING
reset()
write_signals([{
    "signal_id": "sig-appserver-stale-active",
    "source": "codex_appserver",
    "event_type": "turn_started",
    "thread_id": "thread-appserver-stale-active",
    "source_quality": "codex_appserver_thread_list_active",
    "status_hint": "active",
    "occurred_at": "2020-01-01T00:00:00Z",
    "evidence": ["thread/list:status=active"],
    "appserver_activity_evidence": ["thread/list:status=active"],
}])
p = run_projector()
candidate = p["runtime_candidates"][0]
assert_case(
    p["global_status"] == "idle"
    and candidate["display_scope"] == "ignored"
    and candidate.get("why_ignored") == "stale_appserver_signal",
    p,
    "stale appserver active ignored",
)

# 3. process_observer only -> observation count, no RUNNING
reset()
write_signals([{"signal_id": "sig-process", "source": "process_observer", "event_type": "observed_active", "pid": 9876, "observation_id": "obs-process", "confidence": 0.82, "message": "codex exec real-work", "status_hint": "observed_active"}])
p = run_projector()
assert_case(p["global_status"] == "idle" and p["counts"]["process_observed"] == 1 and p["counts"]["observed_active"] == 1, p, "process observer only")

# 4. private global-only active -> no RUNNING
reset()
write_signals([{"signal_id": "sig-private-global", "source": "codex_private_probe", "event_type": "private_active", "confidence": 0.9, "source_quality": "global_private_metadata", "status_hint": "active"}])
p = run_projector()
assert_case(p["global_status"] == "idle" and all(c["display_scope"] != "active_execution" for c in p["runtime_candidates"]), p, "private global only")

# 5. stale private thread-scoped -> no RUNNING
reset()
write_signals([{"signal_id": "sig-private-stale", "source": "codex_private_probe", "event_type": "private_active", "thread_id": "thread-stale", "confidence": 0.78, "source_quality": "thread_private_metadata", "occurred_at": "2020-01-01T00:00:00Z", "status_hint": "active"}])
p = run_projector()
assert_case(p["global_status"] == "idle", p, "private stale")

# 6. hook stale + appserver idle -> no RUNNING
reset()
write_task("task-hook-stale", "running")
write_binding("turn-hook-stale", "task-hook-stale", age=120)
write_signals([
    {"signal_id": "sig-hook-stale", "source": "codex_hook", "event_type": "item_started", "task_id": "task-hook-stale", "turn_id": "turn-hook-stale", "occurred_at": "2020-01-01T00:00:00Z"},
    {"signal_id": "sig-appserver-idle", "source": "codex_appserver", "event_type": "unknown", "thread_id": "thread-idle", "source_quality": "codex_appserver_thread_list_status", "occurred_at": "2020-01-01T00:00:00Z"},
])
p = run_projector()
assert_case(p["global_status"] == "idle" and p["counts"]["running"] == 0, p, "hook stale appserver idle")

# 7. hook + appserver agree -> high-score RUNNING
reset()
write_task("task-agree", "running")
write_binding("turn-agree", "task-agree", thread_id="thread-agree")
write_signals([
    {"signal_id": "sig-agree-hook", "source": "codex_hook", "event_type": "item_started", "task_id": "task-agree", "turn_id": "turn-agree", "thread_id": "thread-agree"},
    {"signal_id": "sig-agree-appserver", "source": "codex_appserver", "event_type": "turn_started", "task_id": "task-agree", "turn_id": "turn-agree", "thread_id": "thread-agree"},
])
p = run_projector()
top = p["runtime_candidates"][0]
assert_case(p["global_status"] == "running" and top["runtime_score"] >= 0.85 and set(top["source_set"]) >= {"codex_hook", "codex_appserver"}, p, "hook appserver agree")

# 8. PermissionRequest fresh -> BLOCKED
reset()
write_task("task-approval", "blocked", reason="needs_human_review", message="approval")
write_binding("turn-approval", "task-approval", event="approval_pending")
write_signals([{"signal_id": "sig-approval", "source": "codex_hook", "event_type": "approval_pending", "task_id": "task-approval", "turn_id": "turn-approval", "reason": "needs_human_review"}])
p = run_projector()
assert_case(p["global_status"] == "blocked" and p["counts"]["blocked"] == 1, p, "permission request")

# 9. old hook blocker stale/resolved -> no permanent red
reset()
write_task("task-old-blocker", "blocked", reason="needs_human_review", message="old approval")
write_binding("turn-old-blocker", "task-old-blocker", age=120, status="released", event="approval_pending")
write_signals([{"signal_id": "sig-old-blocker", "source": "codex_hook", "event_type": "approval_pending", "task_id": "task-old-blocker", "turn_id": "turn-old-blocker", "occurred_at": "2020-01-01T00:00:00Z", "reason": "needs_human_review"}])
p = run_projector()
assert_case(p["global_status"] == "idle" and p["counts"]["blocked"] == 0, p, "old hook blocker")

# 10. done_unverified -> PENDING
reset()
write_task("task-pending", "done_unverified", done_at=stamp())
write_signals([])
p = run_projector()
assert_case(p["global_status"] == "pending" and p["global_display_title"] == "PENDING", p, "done unverified")

# 11. verify -> DONE
reset()
write_task("task-done", "done_verified", done_at=stamp(), verified_at=stamp())
write_signals([])
p = run_projector()
assert_case(p["global_status"] == "done_verified" and p["global_display_title"] == "DONE", p, "done verified")

# 12. old writer metadata -> writer_status=old_writer
reset()
ui_state_path.write_text(json.dumps({
    "schema_version": "0.1",
    "source": "state_projector",
    "projector_version": "M3.2",
    "projector_generated_at": stamp(),
    "projector_code_hash": "sha256:old",
    "global_status": "idle",
    "lamp_status": "idle",
    "global_display_title": "IDLE",
    "state_confidence": 1,
    "counts": {},
    "tasks": [],
    "observations": [],
    "diagnostics": {},
}), encoding="utf-8")
check = subprocess.run([str(check_script)], env={**os.environ, "TASKLIGHT_STATE_PROJECTOR_PROCESS_COUNT_OVERRIDE": "1"}, text=True, capture_output=True, check=False)
assert_case("writer_status=old_writer" in check.stdout, {"check": check.stdout, "stderr": check.stderr}, "old writer")

# 13. multiple projectors -> writer_status=multiple_writers
reset()
write_signals([])
p = run_projector()
check = subprocess.run([str(check_script)], env={**os.environ, "TASKLIGHT_STATE_PROJECTOR_PROCESS_COUNT_OVERRIDE": "2"}, text=True, capture_output=True, check=False)
assert_case("writer_status=multiple_writers" in check.stdout, {"check": check.stdout, "stderr": check.stderr}, "multiple writers")

# 14. false-positive process entries remain diagnostic only
reset()
write_signals([{"signal_id": "sig-false-process", "source": "process_observer", "event_type": "observed_active", "pid": 2222, "observation_id": "obs-false", "confidence": 0.95, "message": "python3 hook_signal_bridge.py --watch", "status_hint": "observed_active"}])
p = run_projector()
assert_case(p["global_status"] == "idle" and p["counts"]["process_observed"] == 0 and p["diagnostics"]["observed_false_positive_count"] >= 1, p, "false process diagnostic")

check = subprocess.run([str(check_script)], env={**os.environ, "TASKLIGHT_STATE_PROJECTOR_PROCESS_COUNT_OVERRIDE": "1"}, text=True, capture_output=True, check=False)
assert_case(
    "top_runtime_candidates_pretty=" in check.stdout
    and "weak_observed_count=" in check.stdout
    and "latest_appserver_state_cause=" in check.stdout,
    {"check": check.stdout, "stderr": check.stderr},
    "check_state_projector candidate diagnostics",
)
PY

echo "smoke_turn_runtime_arbiter: ok"
