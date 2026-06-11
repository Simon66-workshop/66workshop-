#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKLIGHT_BIN="$ROOT_DIR/tasklight"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-smoke-ttl.XXXXXX")"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-smoke-ttl-logs.XXXXXX")"

cleanup() {
  rm -rf "$STATE_DIR" "$TMP_DIR"
}
trap cleanup EXIT

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_REFRESH_SECONDS=0.1
export TASKLIGHT_VERIFICATION_TTL_SECONDS=1

payload="$("$TASKLIGHT_BIN" start --title "TTL gate" --print-id 2>"$TMP_DIR/start.err")"
task_id="$(printf '%s' "$payload" | python3 -c 'import json, sys; print(json.load(sys.stdin)["task_id"])')"
grep -q "$task_id" "$TMP_DIR/start.err"

"$TASKLIGHT_BIN" done --task-id "$task_id" --summary "awaiting acceptance" >/dev/null
sleep 2

status_json="$("$TASKLIGHT_BIN" status)"
python3 -c '
import json
import sys

task_id, payload = sys.argv[1:3]
state = json.loads(payload)
task = next(item for item in state["tasks"] if item["task_id"] == task_id)
assert task["status"] == "stale", task
assert task["sound_type"] == "blocked", task
assert task["last_error"] == "acceptance gate expired", task
assert state["global_status"] == "blocked", state["global_status"]
assert state["counts"]["stale"] == 1, state["counts"]
assert state["counts"]["pending_verify_count"] == 0, state["counts"]
' "$task_id" "$status_json"

echo "smoke_ttl: ok"
