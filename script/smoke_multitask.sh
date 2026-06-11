#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKLIGHT_BIN="$ROOT_DIR/tasklight"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-smoke-multitask.XXXXXX")"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-smoke-multitask-logs.XXXXXX")"

cleanup() {
  rm -rf "$STATE_DIR" "$TMP_DIR"
}
trap cleanup EXIT

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_REFRESH_SECONDS=0.1

start_task() {
  local title="$1"
  local stderr_file="$2"
  local payload task_id
  payload="$("$TASKLIGHT_BIN" start --title "$title" --print-id 2>"$stderr_file")"
  task_id="$(printf '%s' "$payload" | python3 -c 'import json, sys; print(json.load(sys.stdin)["task_id"])')"
  grep -q "$task_id" "$stderr_file"
  printf '%s' "$task_id"
}

task_a_stderr="$TMP_DIR/a.err"
task_b_stderr="$TMP_DIR/b.err"
task_c_stderr="$TMP_DIR/c.err"

task_a="$(start_task "Smoke A" "$task_a_stderr")"
task_b="$(start_task "Smoke B" "$task_b_stderr")"
task_c="$(start_task "Smoke C" "$task_c_stderr")"

"$TASKLIGHT_BIN" done --task-id "$task_a" --summary "awaiting acceptance" >/dev/null
"$TASKLIGHT_BIN" block --task-id "$task_b" --reason missing_input --message "blocked by smoke" --evidence "smoke_multitask" >/dev/null

status_json="$("$TASKLIGHT_BIN" status)"
python3 -c '
import json
import sys

task_a, task_b, task_c, payload = sys.argv[1:5]
state = json.loads(payload)

assert state["global_status"] == "blocked", state["global_status"]
assert state["counts"]["pending_verify_count"] == 1, state["counts"]

by_id = {task["task_id"]: task for task in state["tasks"]}
assert by_id[task_a]["status"] == "done_unverified", by_id[task_a]
assert by_id[task_b]["status"] == "blocked", by_id[task_b]
assert by_id[task_c]["status"] == "running", by_id[task_c]
assert state["counts"]["blocked"] == 1, state["counts"]
assert state["counts"]["running"] == 1, state["counts"]
assert state["counts"]["done_unverified"] == 1, state["counts"]
' "$task_a" "$task_b" "$task_c" "$status_json"

echo "smoke_multitask: ok"
