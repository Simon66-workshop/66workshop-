#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-hook-agent-XXXXXX")"
LABEL="com.66tasklight.hook-bridge.smoke.$$"
DIRECT_BRIDGE_PID=""
BRIDGE_MODE="launch_agent"

cleanup() {
  if [ -n "$DIRECT_BRIDGE_PID" ]; then
    kill "$DIRECT_BRIDGE_PID" >/dev/null 2>&1 || true
    wait "$DIRECT_BRIDGE_PID" >/dev/null 2>&1 || true
  fi
  TASKLIGHT_HOOK_BRIDGE_LABEL="$LABEL" TASKLIGHT_STATE_DIR="$STATE_DIR" "$ROOT_DIR/script/uninstall_hook_bridge_launch_agent.sh" >/dev/null 2>&1 || true
  rm -rf "$STATE_DIR"
}
trap cleanup EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_SIGNAL_SPOOL_DIR="$STATE_DIR/signals"
export TASKLIGHT_TURN_BINDINGS_DIR="$STATE_DIR/turn_bindings"
export TASKLIGHT_HOOK_BRIDGE_OFFSETS_PATH="$STATE_DIR/hook_bridge_offsets.json"
export TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH="$STATE_DIR/hook_bridge_health.json"
export TASKLIGHT_HOOK_BRIDGE_LOG_DIR="$STATE_DIR/logs"
export TASKLIGHT_HOOK_BRIDGE_LABEL="$LABEL"
export TASKLIGHT_HOOK_BRIDGE_COALESCE_SECONDS=2
export TASKLIGHT_HOOK_TURN_LEASE_SECONDS=60
export TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS=6
export TASKLIGHT_HOOK_SIGNAL_MAX_AGE_SECONDS=86400

mkdir -p "$TASKLIGHT_SIGNAL_SPOOL_DIR"
SIGNALS="$TASKLIGHT_SIGNAL_SPOOL_DIR/smoke.jsonl"

append_signal() {
  local event_type="$1"
  local turn_id="$2"
  local raw_ref="${3:-$event_type}"
  python3 - "$SIGNALS" "$event_type" "$turn_id" "$raw_ref" <<'PY'
import json
import sys
import time
from pathlib import Path

path = Path(sys.argv[1])
event_type = sys.argv[2]
turn_id = sys.argv[3]
raw_ref = sys.argv[4]
payload = {
    "source": "codex_hook",
    "event_type": event_type,
    "turn_id": turn_id,
    "event_time": time.time(),
    "confidence": 0.85,
    "source_quality": "codex_hook_event",
    "raw_event_ref": raw_ref,
    "evidence": [f"codex_hook:{event_type}"],
}
path.parent.mkdir(parents=True, exist_ok=True)
with path.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n")
PY
}

wait_for_status() {
  local expected="$1"
  local deadline=$((SECONDS + 12))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if "$ROOT_DIR/script/check_hook_bridge_launch_agent.sh" | grep -q "^STATUS=$expected$"; then
      return 0
    fi
    sleep 0.5
  done
  "$ROOT_DIR/script/check_hook_bridge_launch_agent.sh"
  return 1
}

wait_for_health_ok() {
  local deadline=$((SECONDS + 12))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if python3 - "$TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH" <<'PY' >/dev/null 2>&1
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
raise SystemExit(0 if payload.get("status") == "ok" else 1)
PY
    then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

start_direct_bridge_watch() {
  python3 "$ROOT_DIR/script/hook_signal_bridge.py" --watch >/dev/null 2>&1 &
  DIRECT_BRIDGE_PID="$!"
  wait_for_health_ok
}

task_for_turn() {
  local turn_id="$1"
  python3 - "$TASKLIGHT_TURN_BINDINGS_DIR" "$turn_id" <<'PY'
import json
import sys
from pathlib import Path

base = Path(sys.argv[1])
turn_id = sys.argv[2]
for path in base.glob("*.json"):
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("turn_id") == turn_id:
        print(payload["task_id"])
        raise SystemExit
raise SystemExit(1)
PY
}

task_status() {
  "$ROOT_DIR/tasklight" show "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])'
}

event_count() {
  local name="$1"
  python3 - "$STATE_DIR/events.jsonl" "$name" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
name = sys.argv[2]
if not path.exists():
    print(0)
    raise SystemExit
events = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
print(sum(1 for event in events if event.get("event_name") == name))
PY
}

wait_for_task_status() {
  local task_id="$1"
  local expected="$2"
  local deadline=$((SECONDS + 12))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ "$(task_status "$task_id" 2>/dev/null || true)" = "$expected" ]; then
      return 0
    fi
    sleep 0.5
  done
  "$ROOT_DIR/tasklight" show "$task_id"
  return 1
}

TASKLIGHT_HOOK_BRIDGE_LABEL="$LABEL" TASKLIGHT_STATE_DIR="$STATE_DIR" "$ROOT_DIR/script/uninstall_hook_bridge_launch_agent.sh" >/dev/null 2>&1 || true
"$ROOT_DIR/script/check_hook_bridge_launch_agent.sh" | grep -q "^STATUS=not_running$"

"$ROOT_DIR/script/install_hook_bridge_launch_agent.sh" >/dev/null
if ! wait_for_status ok; then
  BRIDGE_MODE="direct_watch_fallback"
  TASKLIGHT_HOOK_BRIDGE_LABEL="$LABEL" TASKLIGHT_STATE_DIR="$STATE_DIR" "$ROOT_DIR/script/uninstall_hook_bridge_launch_agent.sh" >/dev/null 2>&1 || true
  start_direct_bridge_watch
fi
python3 - "$TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["status"] == "ok", payload
PY

append_signal "turn_started" "turn-agent" "turn-start"
for index in 1 2 3 4 5; do
  append_signal "item_started" "turn-agent" "item-started-$index"
done
sleep 4
task_id="$(task_for_turn turn-agent)"
wait_for_task_status "$task_id" running
heartbeat_count="$(event_count heartbeat)"
if [ "$heartbeat_count" -gt 2 ]; then
  echo "expected coalesced heartbeat_count <= 2, got $heartbeat_count" >&2
  exit 1
fi

append_signal "approval_pending" "turn-blocked" "approval"
sleep 3
blocked_task="$(task_for_turn turn-blocked)"
wait_for_task_status "$blocked_task" blocked

append_signal "turn_started" "turn-stop" "stop-start"
sleep 2
stop_task="$(task_for_turn turn-stop)"
wait_for_task_status "$stop_task" running
append_signal "stop" "turn-stop" "stop"
sleep 3
wait_for_task_status "$stop_task" done_unverified

"$ROOT_DIR/tasklight" verify --task-id "$stop_task" >/dev/null
wait_for_task_status "$stop_task" done_verified

if [ "$BRIDGE_MODE" = "launch_agent" ]; then
  "$ROOT_DIR/script/uninstall_hook_bridge_launch_agent.sh" >/dev/null
  "$ROOT_DIR/script/check_hook_bridge_launch_agent.sh" | grep -q "^STATUS=not_running$"
else
  kill "$DIRECT_BRIDGE_PID" >/dev/null 2>&1 || true
  wait "$DIRECT_BRIDGE_PID" >/dev/null 2>&1 || true
  DIRECT_BRIDGE_PID=""
fi

echo "smoke_hook_bridge_launch_agent: ok mode=$BRIDGE_MODE"
