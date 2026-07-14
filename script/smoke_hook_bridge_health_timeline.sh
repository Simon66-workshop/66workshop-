#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-bridge-health-XXXXXX")"
BRIDGE_PID=""
cleanup() {
  if [ -n "$BRIDGE_PID" ]; then
    kill "$BRIDGE_PID" >/dev/null 2>&1 || true
    wait "$BRIDGE_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$STATE_DIR"
}
trap cleanup EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_SIGNAL_SPOOL_DIR="$STATE_DIR/signals"
export TASKLIGHT_TURN_BINDINGS_DIR="$STATE_DIR/turn_bindings"
export TASKLIGHT_HOOK_BRIDGE_OFFSETS_PATH="$STATE_DIR/hook_bridge_offsets.json"
export TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH="$STATE_DIR/hook_bridge_health.json"
export TASKLIGHT_HOOK_SIGNAL_MAX_AGE_SECONDS=86400
export TASKLIGHT_HOOK_BRIDGE_POLL_SECONDS=0.2
export TASKLIGHT_HOOK_BRIDGE_MAX_SIGNALS_PER_CYCLE=80
mkdir -p "$TASKLIGHT_SIGNAL_SPOOL_DIR"
SIGNALS="$TASKLIGHT_SIGNAL_SPOOL_DIR/timeline.jsonl"

append_signal() {
  python3 - "$SIGNALS" "$1" "$2" <<'PY'
import json
import sys
import time
from pathlib import Path

path = Path(sys.argv[1])
payload = {
    "source": "codex_hook",
    "event_type": sys.argv[2],
    "turn_id": sys.argv[3],
    "event_time": time.time(),
    "confidence": 0.85,
    "source_quality": "codex_hook_event",
    "raw_event_ref": sys.argv[2],
}
with path.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n")
PY
}

health() {
  python3 "$ROOT_DIR/script/hook_bridge_health.py" \
    --signal-dir "$TASKLIGHT_SIGNAL_SPOOL_DIR" \
    --offsets-path "$TASKLIGHT_HOOK_BRIDGE_OFFSETS_PATH" \
    --health-path "$TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH" \
    --process-alive "$1" \
    --launchctl-status "$2" \
    --stale-threshold-sec 1 \
    --idle-threshold-sec 3
}

has_line() {
  local text="$1"
  local expected="$2"
  [[ $'\n'"$text"$'\n' == *$'\n'"$expected"$'\n'* ]]
}

python3 "$ROOT_DIR/script/hook_signal_bridge.py" --watch >/dev/null 2>&1 &
BRIDGE_PID="$!"
deadline=$((SECONDS + 10))
while [ ! -s "$TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH" ] && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.1; done
[ -s "$TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH" ]

append_signal turn_started timeline-1
append_signal item_started timeline-2
append_signal item_completed timeline-3
deadline=$((SECONDS + 10))
while [ "$SECONDS" -lt "$deadline" ]; do
  processed="$(jq '.processed_count // 0' "$TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH" 2>/dev/null || echo 0)"
  [ "$processed" -ge 3 ] && break
  sleep 0.2
done
[ "$(jq '.processed_count // 0' "$TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH")" -ge 3 ]
health_output="$(health yes running)"
if ! has_line "$health_output" "STATUS=ok" && ! has_line "$health_output" "STATUS=idle"; then
  printf '%s\n' "$health_output" >&2
  exit 1
fi
has_line "$health_output" "pending_signal_count=0"

sleep 2
idle_output="$(health yes running)"
if ! has_line "$idle_output" "STATUS=idle" && ! has_line "$idle_output" "STATUS=ok"; then
  printf '%s\n' "$idle_output" >&2
  exit 1
fi

kill "$BRIDGE_PID" >/dev/null 2>&1 || true
wait "$BRIDGE_PID" >/dev/null 2>&1 || true
BRIDGE_PID=""
append_signal item_started pending-1
sleep 2
stale_output="$(health yes running)"
has_line "$stale_output" "STATUS=stale"
has_line "$stale_output" "final_status_reason=pending_input_not_processed_within_threshold"

echo "smoke_hook_bridge_health_timeline=ok"
