#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-projector-cache-XXXXXX")"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

python3 - "$ROOT_DIR" "$STATE_DIR" <<'PY'
import json
import sys
import time
from pathlib import Path

root = Path(sys.argv[1])
state = Path(sys.argv[2])
tasks = state / "tasks"
bindings = state / "turn_bindings"
tasks.mkdir(parents=True)
bindings.mkdir(parents=True)
for index in range(180):
    (tasks / f"task-{index}.json").write_text(json.dumps({"task_id": f"task-{index}", "status": "done_verified"}), encoding="utf-8")
    (bindings / f"binding-{index}.json").write_text(json.dumps({"task_id": f"task-{index}", "turn_id": f"turn-{index}", "status": "released"}), encoding="utf-8")

sys.path.insert(0, str(root / "script"))
import state_projector as projector

first_tasks = projector.load_tasks(state)
first_bindings = projector.load_bindings(state)
assert len(first_tasks[0]) == 180, first_tasks
assert len(first_bindings[3]) == 180, first_bindings

original_load_json = projector.load_json
def unexpected_read(*_args, **_kwargs):
    raise AssertionError("unchanged directory should use cached decoded snapshot")
projector.load_json = unexpected_read
assert projector.load_tasks(state) == first_tasks
assert projector.load_bindings(state) == first_bindings

projector.load_json = original_load_json
time.sleep(0.002)
(tasks / "task-new.json").write_text(json.dumps({"task_id": "task-new", "status": "running"}), encoding="utf-8")
assert len(projector.load_tasks(state)[0]) == 181

ui_payload = {
    "global_status": "idle",
    "lamp_status": "idle",
    "global_display_title": "IDLE",
    "counts": {},
    "tasks": [],
    "observations": [],
    "quota": {},
    "diagnostics": {},
    "runtime_candidates": [],
}
ui_path = state / "ui_state.json"
assert projector.write_ui_state_if_needed(ui_path, ui_payload) is True
assert projector.write_ui_state_if_needed(ui_path, ui_payload) is False
ui_payload["global_status"] = "running"
assert projector.write_ui_state_if_needed(ui_path, ui_payload) is True
PY

echo "smoke_state_projector_snapshot_cache: ok"
