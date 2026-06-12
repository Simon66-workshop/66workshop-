#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIDGE="$ROOT_DIR/script/hook_signal_bridge.py"
PROJECTOR="$ROOT_DIR/script/state_projector.py"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-stop-guard-XXXXXX")"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_SIGNAL_SPOOL_DIR="$STATE_DIR/signals"
export TASKLIGHT_TURN_BINDINGS_DIR="$STATE_DIR/turn_bindings"
export TASKLIGHT_HOOK_BRIDGE_OFFSETS_PATH="$STATE_DIR/hook_bridge_offsets.json"
export TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH="$STATE_DIR/hook_bridge_health.json"
export TASKLIGHT_UI_STATE_PATH="$STATE_DIR/ui_state.json"
export TASKLIGHT_STATE_PROJECTOR_HEALTH_PATH="$STATE_DIR/state_projector_health.json"
export TASKLIGHT_NORMALIZED_SIGNALS_PATH="$STATE_DIR/normalized_signals.jsonl"
export TASKLIGHT_HOOK_TURN_LEASE_SECONDS=30
export TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS=1
export TASKLIGHT_HOOK_SIGNAL_MAX_AGE_SECONDS=86400
export TASKLIGHT_HOOK_BRIDGE_COALESCE_SECONDS=30
export TASKLIGHT_HOOK_ACTIVE_DISPLAY_TTL_SECONDS=12
export TASKLIGHT_APPSERVER_THREAD_OBSERVER_DISABLED=1

mkdir -p "$TASKLIGHT_SIGNAL_SPOOL_DIR"
SIGNALS="$TASKLIGHT_SIGNAL_SPOOL_DIR/unknown.jsonl"

append_signal() {
  local event_type="$1"
  local turn_id="$2"
  local extra="${3-}"
  if [[ -z "$extra" ]]; then
    extra="{}"
  fi
  python3 - "$SIGNALS" "$event_type" "$turn_id" "$extra" <<'PY'
import json
import sys
import time
from pathlib import Path

path = Path(sys.argv[1])
event_type = sys.argv[2]
turn_id = sys.argv[3] or None
extra = json.loads(sys.argv[4])
payload = {
    "source": "codex_hook",
    "event_type": event_type,
    "turn_id": turn_id,
    "thread_id": "thread-stop-guard" if turn_id else None,
    "item_id": f"{event_type}-{time.time_ns()}",
    "event_time": time.time(),
    "confidence": 0.95,
    "source_quality": "codex_hook_event",
    "raw_event_ref": event_type,
    "evidence": [f"codex_hook:{event_type}"],
}
payload.update(extra)
path.parent.mkdir(parents=True, exist_ok=True)
with path.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n")
PY
}

run_bridge() {
  python3 "$BRIDGE" --once >/dev/null
}

run_projector() {
  python3 "$PROJECTOR" --once >/dev/null
}

task_for_turn() {
  local turn_id="$1"
  python3 - "$TASKLIGHT_TURN_BINDINGS_DIR" "$turn_id" <<'PY'
import json
import sys
from pathlib import Path

for path in Path(sys.argv[1]).glob("*.json"):
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("turn_id") == sys.argv[2]:
        print(payload["task_id"])
        raise SystemExit
raise SystemExit(1)
PY
}

task_status() {
  "$ROOT_DIR/tasklight" show "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])'
}

binding_value() {
  local turn_id="$1"
  local key="$2"
  python3 - "$TASKLIGHT_TURN_BINDINGS_DIR" "$turn_id" "$key" <<'PY'
import json
import sys
from pathlib import Path

for path in Path(sys.argv[1]).glob("*.json"):
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("turn_id") == sys.argv[2]:
        value = payload.get(sys.argv[3])
        print("" if value is None else value)
        raise SystemExit
raise SystemExit(1)
PY
}

assert_ui() {
  local expr="$1"
  python3 - "$TASKLIGHT_UI_STATE_PATH" "$expr" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
scope = {"payload": payload}
assert eval(sys.argv[2], {}, scope), json.dumps(payload, indent=2)
PY
}

processed_decisions_for_turn() {
  local turn_id="$1"
  python3 - "$TASKLIGHT_HOOK_BRIDGE_OFFSETS_PATH" "$turn_id" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for item in payload.get("processed", {}).values():
    if item.get("turn_id") == sys.argv[2]:
        print(f"{item.get('event_type')}:{item.get('decision')}")
PY
}

append_signal "turn_started" "turn-soft"
run_bridge
task_soft="$(task_for_turn turn-soft)"
[[ "$(task_status "$task_soft")" == "running" ]]

append_signal "item_completed" "turn-soft"
run_bridge
[[ "$(task_status "$task_soft")" == "running" ]]

sleep 1.2
run_bridge
[[ "$(task_status "$task_soft")" == "cancelled" ]]
[[ "$(binding_value turn-soft release_kind)" == "soft_timeout" ]]
[[ "$(binding_value turn-soft allow_late_stop)" == "True" || "$(binding_value turn-soft allow_late_stop)" == "true" ]]

append_signal "stop" "turn-soft"
run_bridge
[[ "$(task_status "$task_soft")" == "done_unverified" ]]
[[ "$(binding_value turn-soft last_bridge_decision)" == "stop_to_done_unverified" ]]

run_projector
assert_ui 'payload["global_status"] == "pending" and payload["global_display_title"] == "PENDING" and payload["counts"]["pending_verify_count"] == 1'

append_signal "stop" "turn-soft"
run_bridge
[[ "$(task_status "$task_soft")" == "done_unverified" ]]
[[ "$(binding_value turn-soft last_bridge_decision)" == "stop_idempotent_done_unverified" ]]

"$ROOT_DIR/tasklight" verify --task-id "$task_soft" >/dev/null
run_projector
assert_ui 'payload["global_status"] == "done_verified" and payload["global_display_title"] == "DONE"'

append_signal "stop" "turn-soft"
run_bridge
[[ "$(task_status "$task_soft")" == "done_verified" ]]
[[ "$(binding_value turn-soft last_bridge_decision)" == "stop_ignored_already_verified" ]]

append_signal "turn_started" "turn-blocked"
run_bridge
task_blocked="$(task_for_turn turn-blocked)"
append_signal "approval_pending" "turn-blocked"
run_bridge
[[ "$(task_status "$task_blocked")" == "blocked" ]]
append_signal "stop" "turn-blocked"
run_bridge
[[ "$(task_status "$task_blocked")" == "blocked" ]]
[[ "$(binding_value turn-blocked last_bridge_decision)" == "stop_after_blocked_diagnostic" ]]

before_total="$("$ROOT_DIR/tasklight" status | python3 -c 'import json,sys; print(json.load(sys.stdin)["counts"]["total"])')"
append_signal "stop" ""
run_bridge
after_total="$("$ROOT_DIR/tasklight" status | python3 -c 'import json,sys; print(json.load(sys.stdin)["counts"]["total"])')"
[[ "$before_total" == "$after_total" ]]

decisions="$(processed_decisions_for_turn turn-soft)"
grep -q "stop:stop_to_done_unverified" <<<"$decisions"
grep -q "stop:stop_idempotent_done_unverified" <<<"$decisions"
grep -q "stop:stop_ignored_already_verified" <<<"$decisions"
if grep -q "stop:heartbeat_coalesced" <<<"$decisions"; then
  echo "stop was coalesced unexpectedly" >&2
  exit 1
fi

"$ROOT_DIR/script/check_hook_bridge.sh" | grep -q "late_stop_recovered_count=1"
"$ROOT_DIR/script/check_hook_bridge.sh" | grep -q "soft_release_count=1"
"$ROOT_DIR/script/check_hook_bridge.sh" | grep -q "latest_stop_decision=stop_after_blocked_diagnostic"

echo "smoke_stop_priority_guard: ok"
