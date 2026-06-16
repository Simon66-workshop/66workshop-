#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTOR="$ROOT_DIR/script/state_projector.py"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-projector-XXXXXX")"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_UI_STATE_PATH="$STATE_DIR/ui_state.json"
export TASKLIGHT_STATE_PROJECTOR_HEALTH_PATH="$STATE_DIR/state_projector_health.json"
export TASKLIGHT_NORMALIZED_SIGNALS_PATH="$STATE_DIR/normalized_signals.jsonl"
export TASKLIGHT_HOOK_ACTIVE_DISPLAY_TTL_SECONDS=12
export TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS=20
export TASKLIGHT_HOOK_TURN_LEASE_SECONDS=60
export TASKLIGHT_OBSERVED_ACTIVE_TTL_SECONDS=8
export TASKLIGHT_DONE_VISIBLE_HOURS=24
export TASKLIGHT_SIGNAL_BUS_MAX_AGE_SECONDS=9999999999
export TASKLIGHT_APPSERVER_THREAD_OBSERVER_DISABLED=1

mkdir -p "$STATE_DIR/tasks" "$STATE_DIR/turn_bindings" "$STATE_DIR/thread_bindings"

write_signals() {
  local payload="${1-[]}"
  python3 - "$TASKLIGHT_NORMALIZED_SIGNALS_PATH" "$payload" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
records = json.loads(sys.argv[2])
path.parent.mkdir(parents=True, exist_ok=True)
with path.open("w", encoding="utf-8") as handle:
    for record in records:
        handle.write(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n")
PY
}

write_task() {
  local task_id="$1"
  local status="$2"
  local title="$3"
  local extra="${4-}"
  if [[ -z "$extra" ]]; then
    extra="{}"
  fi
  python3 - "$STATE_DIR/tasks/$task_id.json" "$task_id" "$status" "$title" "$extra" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

path = Path(sys.argv[1])
task_id = sys.argv[2]
status = sys.argv[3]
title = sys.argv[4]
extra = json.loads(sys.argv[5])
now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
payload = {
    "schema_version": 3,
    "task_id": task_id,
    "short_task_id": task_id[-8:],
    "title": title,
    "slug": title.lower().replace(" ", "-")[:24],
    "status": status,
    "raw_status": status,
    "effective_status": status,
    "phase": "smoke",
    "progress": 0.4,
    "created_at": now,
    "started_at": now,
    "updated_at": now,
    "heartbeat_at": now,
    "ttl_seconds": 300,
}
payload.update(extra)
path.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
PY
}

write_binding() {
  local turn_id="$1"
  local task_id="$2"
  local status="$3"
  local age="$4"
  local event="${5:-item_started}"
  python3 - "$STATE_DIR/turn_bindings/hook_unknown_${turn_id}.json" "$turn_id" "$task_id" "$status" "$age" "$event" <<'PY'
import json
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

path = Path(sys.argv[1])
turn_id = sys.argv[2]
task_id = sys.argv[3]
status = sys.argv[4]
age = float(sys.argv[5])
event = sys.argv[6]
last = datetime.now(timezone.utc) - timedelta(seconds=age)
stamp = last.replace(microsecond=0).isoformat().replace("+00:00", "Z")
payload = {
    "schema_version": "0.1",
    "source_key": f"hook:unknown:{turn_id}",
    "canonical_identity": f"turn:{turn_id}",
    "aliases": [],
    "task_id": task_id,
    "turn_id": turn_id,
    "thread_id": None,
    "session_id": None,
    "title": f"Codex turn {turn_id[:8]}",
    "cwd": "/tmp/projector",
    "status": status,
    "phase": event,
    "last_signal_event": event,
    "last_signal_at": stamp,
    "created_at": stamp,
    "updated_at": stamp,
    "signal_count": 1,
}
path.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
PY
}

write_thread_binding() {
  local thread_id="$1"
  local task_id="$2"
  local status="$3"
  local age="$4"
  local extra="${5-}"
  if [[ -z "$extra" ]]; then
    extra="{}"
  fi
  python3 - "$STATE_DIR/thread_bindings/thread_${thread_id}.json" "$thread_id" "$task_id" "$status" "$age" "$extra" <<'PY'
import json
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

path = Path(sys.argv[1])
thread_id = sys.argv[2]
task_id = sys.argv[3]
status = sys.argv[4]
age = float(sys.argv[5])
extra = json.loads(sys.argv[6])
updated = datetime.now(timezone.utc) - timedelta(seconds=age)
stamp = updated.replace(microsecond=0).isoformat().replace("+00:00", "Z")
payload = {
    "thread_id": thread_id,
    "task_id": task_id,
    "title": f"Current thread {thread_id[:8]}",
    "cwd": "/tmp/projector",
    "status": status,
    "created_at": stamp,
    "updated_at": stamp,
}
payload.update(extra)
path.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
PY
}

run_projector() {
  python3 "$PROJECTOR" --once >/dev/null
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

assert_check_output() {
  local expr="$1"
  local output
  output="$(TASKLIGHT_STATE_PROJECTOR_MAX_AGE_SECONDS=1 "$ROOT_DIR/script/check_state_projector.sh")"
  CHECK_OUTPUT="$output" python3 - "$expr" <<'PY'
import os
import sys
text = os.environ["CHECK_OUTPUT"]
expr = sys.argv[1]
scope = {"text": text}
assert eval(expr, {}, scope), text
PY
}

write_task "legacy-running" "running" "Legacy running only"
run_projector
assert_ui 'payload["global_status"] == "running" and any(t["task_id"] == "legacy-running" and t["display_scope"] == "active_execution" for t in payload["tasks"])'

write_binding "turn-signal-only" "hook-signal-only" "active" 1 "item_started"
write_signals '[{"signal_id":"sig-signal-only","source":"codex_hook","event_type":"item_started","task_id":"hook-signal-only","turn_id":"turn-signal-only","occurred_at":"2099-01-01T00:00:00Z","confidence":0.95,"thread_scoped":false,"turn_scoped":true,"source_quality":"smoke","evidence":["signal-only"],"conflicts":[]}]'
run_projector
assert_ui 'payload["global_status"] == "running" and any(t["task_id"] == "hook-signal-only" and t["source"] == "codex_hook" and t["display_scope"] == "active_execution" for t in payload["tasks"])'
assert_ui 'any(t["task_id"] == "hook-signal-only" and t["canonical_identity"] == "turn:turn-signal-only" for t in payload["tasks"])'
assert_check_output '"signal_bus_status=readable" in text and "signal_bus_record_count=1" in text and "\"codex_hook\":1" in text'
assert_ui 'any(t["task_id"] == "legacy-running" and t["display_scope"] == "released" and str(t["state_cause"]).startswith("compat:no_signal:running") for t in payload["tasks"])'

write_task "hook-fresh" "running" "Codex turn fresh"
write_binding "turn-fresh" "hook-fresh" "active" 2 "item_started"
write_signals '[{"signal_id":"sig-hook-fresh","source":"codex_hook","event_type":"item_started","task_id":"hook-fresh","turn_id":"turn-fresh","occurred_at":"2099-01-01T00:00:00Z","confidence":0.95,"thread_scoped":false,"turn_scoped":true,"source_quality":"smoke","evidence":["fresh"],"conflicts":[]}]'
run_projector
assert_ui 'payload["global_status"] == "running" and payload["counts"]["running"] == 1'
assert_ui '"active_execution" in payload["diagnostics"]["projector_reason"]'
assert_check_output '"global_status=running" in text and "display_title=RUNNING" in text and "projector_reason=active_execution" in text and "counts=" in text'

write_binding "turn-fresh" "hook-fresh" "active" 30 "item_started"
write_signals '[{"signal_id":"sig-hook-stale","source":"codex_hook","event_type":"item_started","task_id":"hook-fresh","turn_id":"turn-fresh","occurred_at":"2020-01-01T00:00:00Z","confidence":0.95,"thread_scoped":false,"turn_scoped":true,"source_quality":"smoke","evidence":["stale"],"conflicts":[]}]'
run_projector
assert_ui 'payload["global_status"] == "idle" and payload["counts"]["running"] == 0'

write_task "hook-completed" "running" "Codex turn completed"
write_binding "turn-completed" "hook-completed" "active" 25 "item_completed"
write_signals '[{"signal_id":"sig-hook-completed","source":"codex_hook","event_type":"item_completed","task_id":"hook-completed","turn_id":"turn-completed","occurred_at":"2020-01-01T00:00:00Z","confidence":0.95,"thread_scoped":false,"turn_scoped":true,"source_quality":"smoke","evidence":["completed"],"conflicts":[]}]'
run_projector
assert_ui 'payload["global_status"] == "idle" and all(t["display_scope"] != "active_execution" for t in payload["tasks"] if t["task_id"] == "hook-completed")'

write_task "hook-stop" "done_unverified" "Codex turn stop"
write_binding "turn-stop" "hook-stop" "released" 1 "stop"
write_signals '[{"signal_id":"sig-hook-stop","source":"codex_hook","event_type":"stop","task_id":"hook-stop","turn_id":"turn-stop","occurred_at":"2099-01-01T00:00:00Z","confidence":0.95,"thread_scoped":false,"turn_scoped":true,"source_quality":"smoke","evidence":["stop"],"conflicts":[]}]'
run_projector
assert_ui 'payload["global_status"] == "pending" and payload["global_display_title"] == "PENDING" and payload["counts"]["pending_verify_count"] == 1'

write_task "hook-stop" "done_verified" "Codex turn stop" '{"verified_at": "2099-01-01T00:00:00Z", "done_at": "2099-01-01T00:00:00Z"}'
write_signals '[{"signal_id":"sig-hook-verify","source":"explicit","event_type":"verified","task_id":"hook-stop","turn_id":"turn-stop","occurred_at":"2099-01-01T00:00:01Z","confidence":1.0,"thread_scoped":false,"turn_scoped":true,"source_quality":"smoke","evidence":["verify"],"conflicts":[]}]'
run_projector
assert_ui 'payload["global_status"] == "done_verified" and payload["counts"]["done_verified_visible"] >= 1'

rm -f "$STATE_DIR/tasks/legacy-running.json"
write_task "old-pending" "done_unverified" "Old pending should expire" '{"done_at": "2020-01-01T00:00:00Z", "updated_at": "2020-01-01T00:00:00Z", "heartbeat_at": "2020-01-01T00:00:00Z"}'
write_signals '[]'
run_projector
assert_ui 'payload["global_status"] == "done_verified" and payload["counts"]["pending_verify_count"] == 0 and payload["counts"]["stale"] >= 1'
assert_ui 'any(t["task_id"] == "old-pending" and t["effective_status"] == "stale" and t["display_scope"] == "stale_blocker" for t in payload["tasks"])'

write_task "hook-block-old" "blocked" "Codex turn old block" '{"reason": "needs_human_review", "message": "old hook block"}'
write_binding "turn-block-old" "hook-block-old" "released" 120 "approval_pending"
write_signals '[{"signal_id":"sig-hook-block-old","source":"hook_bridge","event_type":"bridge_blocked","task_id":"hook-block-old","turn_id":"turn-block-old","occurred_at":"2020-01-01T00:00:00Z","confidence":0.95,"thread_scoped":false,"turn_scoped":true,"source_quality":"smoke","reason":"needs_human_review","evidence":["old-block"],"conflicts":[]}]'
run_projector
assert_ui 'payload["global_status"] == "done_verified" and all(t["display_scope"] != "open_blocker" for t in payload["tasks"] if t["task_id"] == "hook-block-old")'
assert_ui 'any(t["task_id"] == "hook-block-old" and t["display_scope"] == "stale_blocker" and t["state_cause"] == "hook:blocker_stale" for t in payload["tasks"]) and payload["counts"]["blocked"] == 0 and payload["counts"]["stale"] >= 1'

write_task "explicit-stale" "stale" "Explicit stale diagnostic" '{"reason": "stale_state", "message": "stale compat"}'
write_signals '[{"signal_id":"sig-explicit-stale","source":"explicit","event_type":"heartbeat","task_id":"explicit-stale","occurred_at":"2099-01-01T00:00:00Z","confidence":0.88,"thread_scoped":false,"turn_scoped":false,"source_quality":"smoke","status_hint":"stale","evidence":["explicit-stale"],"conflicts":[]}]'
run_projector
assert_ui 'any(t["task_id"] == "explicit-stale" and t["display_scope"] == "stale_blocker" and t["state_cause"] == "task:stale" for t in payload["tasks"]) and payload["global_status"] == "done_verified" and payload["counts"]["blocked"] == 0 and payload["counts"]["stale"] >= 1'

write_task "explicit-block" "blocked" "Explicit blocked" '{"reason": "missing_input", "message": "explicit block", "evidence": "smoke"}'
write_signals '[{"signal_id":"sig-explicit-block","source":"explicit","event_type":"blocked","task_id":"explicit-block","occurred_at":"2099-01-01T00:00:00Z","confidence":1.0,"thread_scoped":false,"turn_scoped":false,"source_quality":"smoke","reason":"missing_input","message":"explicit block","evidence":["explicit-block"],"conflicts":[]}]'
run_projector
assert_ui 'payload["global_status"] == "blocked" and payload["counts"]["blocked"] == 1'
rm -f "$STATE_DIR/tasks/explicit-block.json"

python3 - "$STATE_DIR/observations_state.json" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
payload = {
    "schema_version": 3,
    "source": "tasklight",
    "source_health": "healthy",
    "lamp_status": "running",
    "global_status": "running",
    "generated_at": now,
    "updated_at": now,
    "counts": {"active": 2, "quiet": 0, "attention": 0, "disappeared": 0, "linked_managed": 0, "total": 2},
    "observations": [
        {"observation_id": "bad", "pid": 1, "ppid": 0, "command": "python3 hook_signal_bridge.py --watch", "command_short": "hook_signal_bridge.py", "title": "bad", "status": "observed_active", "confidence": 0.95, "last_seen_at": now},
        {"observation_id": "good", "pid": 2, "ppid": 0, "command": "codex exec real-work", "command_short": "codex exec real-work", "title": "good", "status": "observed_active", "confidence": 0.82, "last_seen_at": now}
    ]
}
Path(sys.argv[1]).write_text(json.dumps(payload), encoding="utf-8")
PY
run_projector
assert_ui 'payload["counts"]["observed_active"] == 0 and all(item["display_scope"] == "history" for item in payload["observations"])'

write_task "mixed-hook" "running" "Mixed hook task"
write_binding "turn-mixed" "mixed-hook" "active" 1 "item_started"
write_signals '[
  {"signal_id":"sig-mixed-hook","source":"codex_hook","event_type":"item_started","task_id":"mixed-hook","turn_id":"turn-mixed","occurred_at":"2099-01-01T00:00:00Z","confidence":0.95,"thread_scoped":false,"turn_scoped":true,"source_quality":"smoke","evidence":["hook"],"conflicts":[]},
  {"signal_id":"sig-mixed-probe","source":"codex_private_probe","event_type":"private_active","thread_id":"thread-mixed","occurred_at":"2099-01-01T00:00:00Z","confidence":0.78,"thread_scoped":true,"turn_scoped":false,"source_quality":"thread_private_metadata","status_hint":"active","evidence":["probe"],"conflicts":[]},
  {"signal_id":"sig-mixed-observer","source":"process_observer","event_type":"observed_active","pid":1234,"observation_id":"obs-mixed","occurred_at":"2099-01-01T00:00:00Z","confidence":0.82,"thread_scoped":false,"turn_scoped":false,"source_quality":"observe_local_process_scan","status_hint":"observed_active","message":"codex exec real-work","evidence":["observer"],"conflicts":[]},
  {"signal_id":"sig-mixed-thread","source":"current_thread_watcher","event_type":"heartbeat","thread_id":"thread-mixed","occurred_at":"2099-01-01T00:00:00Z","confidence":0.88,"thread_scoped":true,"turn_scoped":false,"source_quality":"thread_private_metadata","status_hint":"running","evidence":["current-thread"],"conflicts":[]}
]'
run_projector
assert_ui 'payload["global_status"] == "running" and payload["diagnostics"]["signal_bus_source_counts"]["codex_hook"] == 1 and payload["diagnostics"]["signal_bus_source_counts"]["codex_private_probe"] == 1 and payload["diagnostics"]["signal_bus_source_counts"]["process_observer"] == 1 and payload["diagnostics"]["signal_bus_source_counts"]["current_thread_watcher"] == 1'
assert_ui 'payload["diagnostics"]["latest_private_probe_status"] == "active" and payload["diagnostics"]["latest_private_probe_quality"] == "thread_private_metadata" and payload["diagnostics"]["current_thread_signal_source"] == "current_thread_watcher" and payload["counts"]["observed_active"] == 1'
assert_ui 'payload["diagnostics"]["latest_turn_binding_canonical_identity"] == "turn:turn-mixed" and payload["diagnostics"]["binding_identity_count"] >= 1'
assert_check_output '"signal_bus_source_counts=" in text and "\"codex_hook\":1" in text and "\"codex_private_probe\":1" in text and "\"current_thread_watcher\":1" in text and "\"process_observer\":1" in text and "latest_private_probe_status=active" in text'

write_task "thread-only" "running" "Current thread only"
write_thread_binding "thread-only" "thread-only" "active" 1
write_signals '[
  {"signal_id":"sig-thread-only","source":"current_thread_watcher","event_type":"heartbeat","task_id":"thread-only","thread_id":"thread-only","occurred_at":"2099-01-01T00:00:00Z","confidence":0.88,"thread_scoped":true,"turn_scoped":false,"source_quality":"thread_private_metadata","status_hint":"running","evidence":["current-thread-only"],"conflicts":[]}
]'
run_projector
assert_ui 'payload["counts"]["running"] == 0 and any(t["task_id"] == "thread-only" and t["display_scope"] == "released" and t["state_cause"] == "current_thread:compat_without_thread_probe" for t in payload["tasks"])'

write_signals '[
  {"signal_id":"sig-thread-only","source":"current_thread_watcher","event_type":"heartbeat","task_id":"thread-only","thread_id":"thread-only","occurred_at":"2099-01-01T00:00:00Z","confidence":0.88,"thread_scoped":true,"turn_scoped":false,"source_quality":"thread_private_metadata","status_hint":"running","evidence":["current-thread-only"],"conflicts":[]},
  {"signal_id":"sig-thread-probe","source":"codex_private_probe","event_type":"private_active","thread_id":"thread-only","occurred_at":"2099-01-01T00:00:00Z","confidence":0.78,"thread_scoped":true,"turn_scoped":false,"source_quality":"thread_private_metadata","status_hint":"active","evidence":["thread-probe"],"conflicts":[]}
]'
run_projector
assert_ui 'payload["global_status"] == "running" and any(t["task_id"] == "thread-only" and t["display_scope"] == "active_execution" and t["state_cause"] == "current_thread:heartbeat" for t in payload["tasks"])'

write_task "thread-turn-anchor" "running" "Current thread turn anchor"
write_thread_binding "thread-turn-anchor" "thread-turn-anchor" "active" 0 '{"task_identity":"turn:turn-thread-anchor","turn_id":"turn-thread-anchor","title":"Current thread turn anchor"}'
write_signals '[
  {"signal_id":"sig-thread-anchor-heartbeat","source":"current_thread_watcher","event_type":"heartbeat","task_id":"thread-turn-anchor","thread_id":"thread-turn-anchor","turn_id":"turn-thread-anchor","occurred_at":"2099-01-01T00:00:00Z","confidence":0.88,"thread_scoped":true,"turn_scoped":true,"source_quality":"thread_private_metadata","status_hint":"running","evidence":["current-thread-turn-anchor"],"conflicts":[]},
  {"signal_id":"sig-thread-anchor-hook","source":"codex_hook","event_type":"item_started","task_id":"hook-thread-turn-anchor","turn_id":"turn-thread-anchor","occurred_at":"2099-01-01T00:00:00Z","confidence":0.95,"thread_scoped":false,"turn_scoped":true,"source_quality":"smoke","evidence":["thread-anchor-hook"],"conflicts":[]}
]'
run_projector
assert_ui 'payload["global_status"] == "running" and any(t["task_id"] == "thread-turn-anchor" and t["display_scope"] == "active_execution" and t["state_cause"] == "current_thread:turn_anchored_heartbeat" for t in payload["tasks"])'
assert_ui 'payload["diagnostics"]["current_thread_task_identity"] == "turn:turn-thread-anchor" and any(t["task_id"] == "thread-turn-anchor" and t["turn_id"] == "turn-thread-anchor" for t in payload["tasks"])'

write_task "cross-thread-idle" "cancelled" "Cross thread idle"
write_signals '[
  {"signal_id":"sig-appserver-current","source":"codex_appserver","event_type":"unknown","thread_id":"thread-only","occurred_at":"2099-01-01T00:00:00Z","confidence":0.0,"thread_scoped":true,"turn_scoped":false,"source_quality":"codex_appserver_thread_list_ignored","status_hint":"notLoaded","evidence":["thread/list:status=notLoaded"],"conflicts":["thread_list_notLoaded"]},
  {"signal_id":"sig-appserver-other","source":"codex_appserver","event_type":"unknown","thread_id":"other-thread-1","occurred_at":"2099-01-01T00:00:00Z","confidence":0.0,"thread_scoped":true,"turn_scoped":false,"source_quality":"codex_appserver_thread_list_ignored","status_hint":"notLoaded","evidence":["thread/list:status=notLoaded"],"conflicts":["thread_list_notLoaded"]}
]'
python3 - "$STATE_DIR/appserver_thread_watcher_health.json" <<'PY'
import json
import sys
from pathlib import Path
payload = {"schema_version":"0.1","status":"ok","last_run_at":"2099-01-01T00:00:00Z","emitted_count":2,"live_threads":1,"updated_at":"2099-01-01T00:00:00Z"}
Path(sys.argv[1]).write_text(json.dumps(payload), encoding="utf-8")
PY
unset TASKLIGHT_APPSERVER_THREAD_OBSERVER_DISABLED
run_projector
assert_ui 'payload["global_status"] != "running" and payload["counts"]["appserver_active"] == 0 and any(o["observation_id"] == "appserver:other-thread-1" and o["display_scope"] == "history" and o["why_ignored"] for o in payload["observations"])'
assert_ui 'payload["diagnostics"]["appserver_live_thread_count"] == 0 and payload["diagnostics"]["appserver_thread_signal_status"] == "bus"'
export TASKLIGHT_APPSERVER_THREAD_OBSERVER_DISABLED=1

python3 - "$STATE_DIR/tasks/old-done.json" <<'PY'
import json
import sys
from pathlib import Path
old = "2020-01-01T00:00:00Z"
payload = {
    "schema_version": 3,
    "task_id": "old-done",
    "title": "Old done",
    "slug": "old-done",
    "status": "done_verified",
    "raw_status": "done_verified",
    "effective_status": "done_verified",
    "created_at": old,
    "started_at": old,
    "updated_at": old,
    "done_at": old,
    "verified_at": old,
}
Path(sys.argv[1]).write_text(json.dumps(payload), encoding="utf-8")
PY
run_projector
assert_ui 'all(t["display_scope"] != "recent_done" for t in payload["tasks"] if t["task_id"] == "old-done")'

write_task "legacy-blocked" "blocked" "Legacy blocked only" '{"reason": "missing_input", "message": "legacy blocked"}'
write_signals '[{"signal_id":"sig-running-wins","source":"codex_hook","event_type":"item_started","task_id":"mixed-hook","turn_id":"turn-mixed","occurred_at":"2099-01-01T00:00:02Z","confidence":0.95,"thread_scoped":false,"turn_scoped":true,"source_quality":"smoke","evidence":["running-wins"],"conflicts":[]}]'
run_projector
assert_ui 'payload["global_status"] == "running" and any(t["task_id"] == "legacy-blocked" and t["display_scope"] == "resolved_blocker" and str(t["state_cause"]).startswith("compat:no_signal:blocked") for t in payload["tasks"])'

python3 - "$TASKLIGHT_UI_STATE_PATH" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["projector_generated_at"] = "2020-01-01T00:00:00Z"
payload.setdefault("diagnostics", {})["projector_reason"] = ["stale_fixture"]
path.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
PY
assert_check_output '"STATUS=stale" in text and "state_projector_fresh=no" in text and "projector_reason=stale_fixture" in text'

echo "smoke_state_projector: ok"
