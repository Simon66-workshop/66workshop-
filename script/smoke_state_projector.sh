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

mkdir -p "$STATE_DIR/tasks" "$STATE_DIR/turn_bindings"

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

write_task "hook-fresh" "running" "Codex turn fresh"
write_binding "turn-fresh" "hook-fresh" "active" 2 "item_started"
run_projector
assert_ui 'payload["global_status"] == "running" and payload["counts"]["running"] == 1'
assert_ui '"active_execution" in payload["diagnostics"]["projector_reason"]'
assert_check_output '"global_status=running" in text and "display_title=RUNNING" in text and "projector_reason=active_execution" in text and "counts=" in text'

write_binding "turn-fresh" "hook-fresh" "active" 30 "item_started"
run_projector
assert_ui 'payload["global_status"] == "idle" and payload["counts"]["running"] == 0'

write_task "hook-completed" "running" "Codex turn completed"
write_binding "turn-completed" "hook-completed" "active" 25 "item_completed"
run_projector
assert_ui 'payload["global_status"] == "idle" and all(t["display_scope"] != "active_execution" for t in payload["tasks"] if t["task_id"] == "hook-completed")'

write_task "hook-stop" "done_unverified" "Codex turn stop"
write_binding "turn-stop" "hook-stop" "released" 1 "stop"
run_projector
assert_ui 'payload["global_status"] == "pending" and payload["global_display_title"] == "PENDING" and payload["counts"]["pending_verify_count"] == 1'

write_task "hook-stop" "done_verified" "Codex turn stop" '{"verified_at": "2099-01-01T00:00:00Z", "done_at": "2099-01-01T00:00:00Z"}'
run_projector
assert_ui 'payload["global_status"] == "done_verified" and payload["counts"]["done_verified_visible"] >= 1'

write_task "hook-block-old" "blocked" "Codex turn old block" '{"reason": "needs_human_review", "message": "old hook block"}'
write_binding "turn-block-old" "hook-block-old" "released" 120 "approval_pending"
run_projector
assert_ui 'payload["global_status"] == "done_verified" and all(t["display_scope"] != "open_blocker" for t in payload["tasks"] if t["task_id"] == "hook-block-old")'

write_task "explicit-block" "blocked" "Explicit blocked" '{"reason": "missing_input", "message": "explicit block", "evidence": "smoke"}'
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
assert_ui 'payload["counts"]["observed_active"] == 1'

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
