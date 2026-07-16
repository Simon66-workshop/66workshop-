#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT_DIR" <<'PY'
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

root = Path(sys.argv[1])
script_dir = root / "script"
sys.path.insert(0, str(script_dir))

for name in (
    "TASKLIGHT_HOOK_ACTIVE_DISPLAY_TTL_SECONDS",
    "TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS",
    "TASKLIGHT_HOOK_TURN_LEASE_SECONDS",
):
    os.environ.pop(name, None)


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


projector = load("tasklight_state_projector_lease_smoke", script_dir / "state_projector.py")
projector_args = projector.build_parser().parse_args(["--once"])
assert projector_args.hook_active_ttl == 300, projector_args.hook_active_ttl
assert projector_args.completed_idle_seconds == 300, projector_args.completed_idle_seconds
assert projector_args.hook_turn_lease_seconds == 300, projector_args.hook_turn_lease_seconds

bridge = load("tasklight_hook_bridge_lease_smoke", script_dir / "hook_signal_bridge.py")
bridge_args = bridge.build_parser().parse_args(["--once"])
assert bridge_args.lease_seconds == 300, bridge_args.lease_seconds
assert bridge_args.completed_idle_release_seconds == 300, bridge_args.completed_idle_release_seconds

# PostToolUse/item_completed is not turn completion. It must retain the same
# bounded lease as the turn instead of dropping RUNNING after a short gap while
# Codex is still reasoning or preparing the next item.
release_after = bridge.binding_release_after_seconds(
    {"last_signal_event": "item_completed"},
    bridge_args.lease_seconds,
    bridge_args.completed_idle_release_seconds,
)
assert release_after == 300, release_after


def stamp(age: float) -> str:
    value = datetime.now(timezone.utc) - timedelta(seconds=age)
    return value.replace(microsecond=0).isoformat().replace("+00:00", "Z")


def project_item_completed(age: float) -> dict:
    with tempfile.TemporaryDirectory(prefix="tasklight-hook-lease-") as tmp:
        state = Path(tmp)
        (state / "tasks").mkdir()
        (state / "turn_bindings").mkdir()
        when = stamp(age)
        task_id = "task-item-completed-lease"
        turn_id = "turn-item-completed-lease"
        (state / "tasks" / f"{task_id}.json").write_text(json.dumps({
            "schema_version": 3,
            "task_id": task_id,
            "title": "Item completed lease",
            "status": "running",
            "raw_status": "running",
            "effective_status": "running",
            "created_at": when,
            "started_at": when,
            "updated_at": when,
            "heartbeat_at": when,
        }), encoding="utf-8")
        (state / "turn_bindings" / "hook_unknown_turn-item-completed-lease.json").write_text(json.dumps({
            "schema_version": "0.1",
            "canonical_identity": f"turn:{turn_id}",
            "task_id": task_id,
            "turn_id": turn_id,
            "status": "active",
            "last_signal_event": "item_completed",
            "last_signal_at": when,
            "created_at": when,
            "updated_at": when,
        }), encoding="utf-8")
        (state / "normalized_signals.jsonl").write_text(json.dumps({
            "signal_id": f"sig-{age}",
            "source": "codex_hook",
            "event_type": "item_completed",
            "task_id": task_id,
            "turn_id": turn_id,
            "occurred_at": when,
            "confidence": 0.95,
            "turn_scoped": True,
            "source_quality": "codex_hook_event",
        }) + "\n", encoding="utf-8")
        env = dict(os.environ)
        env.update({
            "TASKLIGHT_STATE_DIR": str(state),
            "TASKLIGHT_UI_STATE_PATH": str(state / "ui_state.json"),
            "TASKLIGHT_STATE_PROJECTOR_HEALTH_PATH": str(state / "state_projector_health.json"),
            "TASKLIGHT_NORMALIZED_SIGNALS_PATH": str(state / "normalized_signals.jsonl"),
            "TASKLIGHT_STATE_PROJECTOR_PROCESS_COUNT_OVERRIDE": "1",
            "TASKLIGHT_SIGNAL_BUS_MAX_AGE_SECONDS": "9999999999",
        })
        subprocess.run(
            [sys.executable, str(script_dir / "state_projector.py"), "--once"],
            check=True,
            env=env,
            stdout=subprocess.DEVNULL,
        )
        return json.loads((state / "ui_state.json").read_text(encoding="utf-8"))


active = project_item_completed(120)
assert active["global_status"] == "running", active
assert any(
    candidate.get("turn_id") == "turn-item-completed-lease"
    and candidate.get("display_scope") == "active_execution"
    for candidate in active.get("runtime_candidates", [])
), active
expired = project_item_completed(301)
assert expired["global_status"] != "running", expired

print("smoke_hook_active_turn_lease: PASS")
PY
