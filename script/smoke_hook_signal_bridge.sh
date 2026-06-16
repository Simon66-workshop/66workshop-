#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIDGE="$ROOT_DIR/script/hook_signal_bridge.py"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-hook-bridge-XXXXXX")"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_SIGNAL_SPOOL_DIR="$STATE_DIR/signals"
export TASKLIGHT_TURN_BINDINGS_DIR="$STATE_DIR/turn_bindings"
export TASKLIGHT_HOOK_BRIDGE_OFFSETS_PATH="$STATE_DIR/hook_bridge_offsets.json"
export TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH="$STATE_DIR/hook_bridge_health.json"
export TASKLIGHT_HOOK_TURN_LEASE_SECONDS=30
export TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS=6
export TASKLIGHT_HOOK_SIGNAL_MAX_AGE_SECONDS=86400

mkdir -p "$TASKLIGHT_SIGNAL_SPOOL_DIR"
SIGNALS="$TASKLIGHT_SIGNAL_SPOOL_DIR/unknown.jsonl"

append_signal() {
  local event_type="$1"
  local turn_id="$2"
  local thread_id="${3:-}"
  local extra="${4:-"{}"}"
  python3 - "$SIGNALS" "$event_type" "$turn_id" "$thread_id" "$extra" <<'PY'
import json
import sys
import time
from pathlib import Path

path = Path(sys.argv[1])
event_type = sys.argv[2]
turn_id = sys.argv[3]
thread_id = sys.argv[4] or None
extra = json.loads(sys.argv[5])
payload = {
    "source": "codex_hook",
    "event_type": event_type,
    "turn_id": turn_id or None,
    "thread_id": thread_id,
    "event_time": int(time.time()),
    "confidence": 0.85,
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

assert_health_ok() {
  python3 - "$TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["status"] == "ok", payload
assert "active_turn_bindings" in payload, payload
PY
}

count_value() {
  local key="$1"
  "$ROOT_DIR/tasklight" status | python3 -c 'import json,sys; p=json.load(sys.stdin); print(p["counts"][sys.argv[1]])' "$key"
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

task_phase() {
  "$ROOT_DIR/tasklight" show "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["phase"])'
}

binding_signal_count() {
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
        print(payload.get("signal_count"))
        raise SystemExit
raise SystemExit(1)
PY
}

binding_cwd() {
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
        print(payload.get("cwd") or "")
        raise SystemExit
raise SystemExit(1)
PY
}

assert_binding_identity() {
  local turn_id="$1"
  local expected_alias="${2:-}"
  python3 - "$TASKLIGHT_TURN_BINDINGS_DIR" "$turn_id" "$expected_alias" <<'PY'
import json
import sys
from pathlib import Path
base = Path(sys.argv[1])
turn_id = sys.argv[2]
expected_alias = sys.argv[3]
for path in base.glob("*.json"):
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("turn_id") == turn_id:
        assert payload.get("canonical_identity") == f"turn:{turn_id}", payload
        assert payload.get("origin_signal_id"), payload
        if expected_alias:
            assert expected_alias in payload.get("aliases", []), payload
        raise SystemExit
raise SystemExit(1)
PY
}

append_signal "item_started" ""
run_bridge
[[ "$(count_value total)" == "0" ]]

append_signal "unknown_event" "turn-unknown"
run_bridge
[[ "$(count_value total)" == "0" ]]

python3 - "$SIGNALS" <<'PY'
import json
import time
import sys
from pathlib import Path
payload = {
    "source": "codex_hook",
    "event_type": "turn_started",
    "turn_id": "turn-dup",
    "thread_id": None,
    "event_time": int(time.time()),
    "confidence": 0.85,
    "source_quality": "codex_hook_event",
    "raw_event_ref": "userPromptSubmit",
}
path = Path(sys.argv[1])
with path.open("a", encoding="utf-8") as handle:
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    handle.write(encoded + "\n")
    handle.write(encoded + "\n")
PY
run_bridge
task_dup="$(task_for_turn turn-dup)"
[[ "$(task_status "$task_dup")" == "running" ]]
[[ "$(binding_signal_count turn-dup)" == "1" ]]

append_signal "turn_started" "turn-a"
run_bridge
assert_health_ok
task_a="$(task_for_turn turn-a)"
[[ "$(task_status "$task_a")" == "running" ]]
assert_binding_identity "turn-a"

binding_count_before="$(find "$TASKLIGHT_TURN_BINDINGS_DIR" -type f -name '*.json' | wc -l | tr -d ' ')"
run_bridge
binding_count_after="$(find "$TASKLIGHT_TURN_BINDINGS_DIR" -type f -name '*.json' | wc -l | tr -d ' ')"
[[ "$binding_count_before" == "$binding_count_after" ]]

append_signal "item_started" "turn-a"
run_bridge
[[ "$(task_status "$task_a")" == "running" ]]
[[ "$(task_phase "$task_a")" == "tool_running" ]]

append_signal "item_completed" "turn-a"
run_bridge
[[ "$(task_status "$task_a")" == "running" ]]
[[ "$(task_phase "$task_a")" == "item_completed" ]]

append_signal "item_started" "turn-a" "" '{"cwd":"/tmp/tasklight-workspace-a"}'
run_bridge
[[ "$(binding_cwd turn-a)" == "/tmp/tasklight-workspace-a" ]]

append_signal "stop" "turn-a"
run_bridge
[[ "$(task_status "$task_a")" == "done_unverified" ]]

"$ROOT_DIR/tasklight" verify --task-id "$task_a" >/dev/null
[[ "$(task_status "$task_a")" == "done_verified" ]]

append_signal "item_started" "turn-a"
run_bridge
[[ "$(task_status "$task_a")" == "done_verified" ]]

append_signal "turn_started" "turn-b" "thread-1"
run_bridge
task_b="$(task_for_turn turn-b)"
assert_binding_identity "turn-b" "appserver:thread-1:turn-b"
append_signal "turn_started" "turn-c" "thread-1"
run_bridge
task_c="$(task_for_turn turn-c)"
assert_binding_identity "turn-c" "appserver:thread-1:turn-c"
[[ "$task_b" != "$task_c" ]]
[[ "$(task_status "$task_b")" == "running" ]]
[[ "$(task_status "$task_c")" == "running" ]]

append_signal "turn_started" "turn-old-pending"
run_bridge
task_old_pending="$(task_for_turn turn-old-pending)"
append_signal "stop" "turn-old-pending"
run_bridge
[[ "$(task_status "$task_old_pending")" == "done_unverified" ]]
export TASKLIGHT_VERIFICATION_TTL_SECONDS=1
sleep 1.2
[[ "$(task_status "$task_old_pending")" == "stale" ]]
append_signal "turn_started" "turn-new-active"
run_bridge
task_new_active="$(task_for_turn turn-new-active)"
[[ "$(task_status "$task_new_active")" == "running" ]]
[[ "$(task_status "$task_old_pending")" == "cancelled" ]]
unset TASKLIGHT_VERIFICATION_TTL_SECONDS

append_signal "approval_pending" "turn-d"
run_bridge
task_d="$(task_for_turn turn-d)"
task_d_json="$("$ROOT_DIR/tasklight" show "$task_d")"
python3 - "$task_d_json" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
assert payload["status"] == "blocked", payload
assert payload["reason"] == "needs_human_review", payload
PY

append_signal "tool_failed" "turn-f"
run_bridge
task_f="$(task_for_turn turn-f)"
task_f_json="$("$ROOT_DIR/tasklight" show "$task_f")"
python3 - "$task_f_json" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
assert payload["status"] == "blocked", payload
assert payload["reason"] == "codex_exit_failed", payload
PY

append_signal "turn_started" "turn-e"
run_bridge
task_e="$(task_for_turn turn-e)"
export TASKLIGHT_HOOK_TURN_LEASE_SECONDS=1
sleep 1.2
run_bridge
[[ "$(task_status "$task_e")" == "cancelled" ]]
[[ "$(task_phase "$task_e")" == "released" ]]
python3 - "$STATE_DIR/events.jsonl" <<'PY'
import json
import sys
from pathlib import Path
events = [json.loads(line) for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line.strip()]
release_events = [event for event in events if event.get("event_name") == "release" or event.get("to") == "cancelled"]
assert release_events, events[-3:]
assert release_events[-1]["sound_type"] == "none", release_events[-1]
PY

export TASKLIGHT_HOOK_TURN_LEASE_SECONDS=30
export TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS=1
append_signal "turn_started" "turn-g"
run_bridge
task_g="$(task_for_turn turn-g)"
append_signal "item_completed" "turn-g"
run_bridge
[[ "$(task_status "$task_g")" == "running" ]]
sleep 1.2
run_bridge
[[ "$(task_status "$task_g")" == "cancelled" ]]
[[ "$(task_phase "$task_g")" == "released" ]]
python3 - "$TASKLIGHT_TURN_BINDINGS_DIR" <<'PY'
import json
import sys
from pathlib import Path
for path in Path(sys.argv[1]).glob("*.json"):
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("turn_id") == "turn-g":
        assert payload.get("release_reason") == "completed_idle_timeout", payload
        raise SystemExit
raise SystemExit(1)
PY

append_signal "item_started" "turn-g"
run_bridge
task_g_reactivated="$(task_for_turn turn-g)"
[[ "$task_g_reactivated" != "$task_g" ]]
[[ "$(task_status "$task_g")" == "cancelled" ]]
[[ "$(task_status "$task_g_reactivated")" == "running" ]]
[[ "$(task_phase "$task_g_reactivated")" == "tool_running" ]]
python3 - "$TASKLIGHT_TURN_BINDINGS_DIR" "$task_g" <<'PY'
import json
import sys
from pathlib import Path
base = Path(sys.argv[1])
previous_task = sys.argv[2]
for path in base.glob("*.json"):
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("turn_id") == "turn-g":
        assert previous_task in payload.get("previous_task_ids", []), payload
        assert payload.get("status") == "active", payload
        assert payload.get("reactivation_count", 0) >= 1, payload
        raise SystemExit
raise SystemExit(1)
PY

"$ROOT_DIR/script/check_hook_bridge.sh" >/dev/null

echo "smoke_hook_signal_bridge: ok"
