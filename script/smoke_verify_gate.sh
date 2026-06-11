#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKLIGHT_BIN="$ROOT_DIR/tasklight"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-smoke-verify.XXXXXX")"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-smoke-verify-logs.XXXXXX")"

cleanup() {
  rm -rf "$STATE_DIR" "$TMP_DIR"
}
trap cleanup EXIT

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_REFRESH_SECONDS=0.1

payload="$("$TASKLIGHT_BIN" start --title "Verify gate" --print-id 2>"$TMP_DIR/start.err")"
task_id="$(printf '%s' "$payload" | python3 -c 'import json, sys; print(json.load(sys.stdin)["task_id"])')"
grep -q "$task_id" "$TMP_DIR/start.err"

done_payload="$("$TASKLIGHT_BIN" done --task-id "$task_id" --summary "awaiting acceptance")"
done_status="$(printf '%s' "$done_payload" | python3 -c 'import json, sys; print(json.load(sys.stdin)["status"])')"
test "$done_status" = "done_unverified"

status_json="$("$TASKLIGHT_BIN" status)"
python3 -c '
import json
import sys

task_id, payload = sys.argv[1:3]
state = json.loads(payload)
task = next(item for item in state["tasks"] if item["task_id"] == task_id)
assert task["status"] == "done_unverified", task
assert state["global_status"] == "running", state["global_status"]
assert state["counts"]["pending_verify_count"] == 1, state["counts"]
' "$task_id" "$status_json"

events_path="$STATE_DIR/events.jsonl"
python3 -c '
import json
import sys
from pathlib import Path

events_path = Path(sys.argv[1])
events = [json.loads(line) for line in events_path.read_text(encoding="utf-8").splitlines() if line.strip()]
assert not any(event.get("to") == "done_verified" for event in events), events
assert not any(event.get("sound_type") == "done_verified" for event in events), events
' "$events_path"

verify_payload="$("$TASKLIGHT_BIN" verify --task-id "$task_id")"
verify_status="$(printf '%s' "$verify_payload" | python3 -c 'import json, sys; print(json.load(sys.stdin)["status"])')"
test "$verify_status" = "done_verified"

status_json="$("$TASKLIGHT_BIN" status)"
python3 -c '
import json
import sys

task_id, payload = sys.argv[1:3]
state = json.loads(payload)
task = next(item for item in state["tasks"] if item["task_id"] == task_id)
assert task["status"] == "done_verified", task
assert state["global_status"] == "done_verified", state["global_status"]
assert state["counts"]["done_verified"] == 1, state["counts"]
assert state["counts"]["active"] == 0, state["counts"]
' "$task_id" "$status_json"

python3 -c '
import json
import sys
from pathlib import Path

events = [json.loads(line) for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line.strip()]
done_verified_events = [event for event in events if event.get("to") == "done_verified"]
assert len(done_verified_events) == 1, done_verified_events
assert done_verified_events[0].get("sound_type") == "done_verified", done_verified_events[0]
done_events = [event for event in events if event.get("to") == "done_unverified"]
assert len(done_events) == 1, done_events
assert done_events[0].get("sound_type") == "none", done_events[0]
' "$events_path"

echo "smoke_verify_gate: ok"
