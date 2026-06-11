#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKLIGHT_BIN="$ROOT_DIR/tasklight"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-smoke-invalid.XXXXXX")"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-smoke-invalid-logs.XXXXXX")"

cleanup() {
  rm -rf "$STATE_DIR" "$TMP_DIR"
}
trap cleanup EXIT

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_REFRESH_SECONDS=0.1

start_task() {
  local title="$1"
  local payload
  payload="$("$TASKLIGHT_BIN" start --title "$title" --print-id 2>>"$TMP_DIR/start.err")"
  printf '%s' "$payload" | python3 -c 'import json, sys; print(json.load(sys.stdin)["task_id"])'
}

task_a="$(start_task "Invalid JSON A")"
task_b="$(start_task "Invalid JSON B")"

task_a_path="$STATE_DIR/tasks/$task_a.json"
python3 -c '
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")
path.write_text(data[: max(0, len(data) // 3)] + "{broken", encoding="utf-8")
' "$task_a_path"

status_json="$("$TASKLIGHT_BIN" status)"
python3 -c '
import json
import sys

task_a, task_b, payload = sys.argv[1:4]
state = json.loads(payload)

assert state["source_health"] in {"healthy", "reconstructed"}, state["source_health"]
assert state["global_status"] in {"running", "idle", "blocked", "done_verified"}, state["global_status"]

invalid = {task["task_id"]: task for task in state["invalid_tasks"]}
valid = {task["task_id"]: task for task in state["tasks"]}

assert task_a in invalid, (invalid, valid)
assert invalid[task_a]["status"] == "invalid_json", invalid[task_a]
assert task_b in valid, (invalid, valid)
assert valid[task_b]["status"] == "running", valid[task_b]
assert state["counts"]["invalid_json"] == 1, state["counts"]
' "$task_a" "$task_b" "$status_json"

show_json="$("$TASKLIGHT_BIN" show "$task_a")"
python3 -c '
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "invalid_json", payload
assert payload["invalid_json_error"], payload
' "$show_json"

"$ROOT_DIR/script/build_and_run.sh" --verify >"$TMP_DIR/verify.out"
grep -q "bundle_path=" "$TMP_DIR/verify.out"
grep -q "app_process_status=" "$TMP_DIR/verify.out"
grep -q "state_dir=" "$TMP_DIR/verify.out"
grep -q "state_json_status=" "$TMP_DIR/verify.out"
grep -q "observations_state_status=" "$TMP_DIR/verify.out"
grep -q "observer_watch_status=" "$TMP_DIR/verify.out"
grep -q "swift_build=success" "$TMP_DIR/verify.out"

echo "smoke_invalid_task_json: ok"
