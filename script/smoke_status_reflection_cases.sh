#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASE_TOOL="$ROOT_DIR/script/status_reflection_case.py"
PROJECTOR="$ROOT_DIR/script/state_projector.py"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-reflection-XXXXXX")"
WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-reflection-workspace-XXXXXX")"
REFLECTION_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-reflection-cases-XXXXXX")"
trap 'rm -rf "$STATE_DIR" "$WORKSPACE" "$REFLECTION_DIR"' EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_UI_STATE_PATH="$STATE_DIR/ui_state.json"
export TASKLIGHT_NORMALIZED_SIGNALS_PATH="$STATE_DIR/normalized_signals.jsonl"
export TASKLIGHT_STATUS_REFLECTION_DIR="$REFLECTION_DIR"
export TASKLIGHT_SIGNAL_BUS_MAX_AGE_SECONDS=9999999999
export TASKLIGHT_STATE_PROJECTOR_PROCESS_COUNT_OVERRIDE=1

mkdir -p "$STATE_DIR/tasks" "$STATE_DIR/turn_bindings" "$STATE_DIR/thread_bindings"

write_ui_state() {
  python3 - "$STATE_DIR/ui_state.json" "$1" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
payload = json.loads(sys.argv[2])
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
PY
}

write_signals() {
  python3 - "$STATE_DIR/normalized_signals.jsonl" "$1" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
payload = json.loads(sys.argv[2])
path.write_text("\n".join(json.dumps(item, sort_keys=True) for item in payload) + "\n", encoding="utf-8")
PY
}

write_task() {
  python3 - "$STATE_DIR/tasks/$1.json" "$1" "$2" "$3" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
task_id = sys.argv[2]
status = sys.argv[3]
extra = json.loads(sys.argv[4])
payload = {
    "schema_version": 3,
    "task_id": task_id,
    "short_task_id": task_id[-8:],
    "title": task_id,
    "slug": task_id,
    "status": status,
    "raw_status": status,
    "effective_status": status,
    "phase": "smoke",
    "progress": 0.1,
    "created_at": "2099-01-01T00:00:00Z",
    "started_at": "2099-01-01T00:00:00Z",
    "updated_at": "2099-01-01T00:00:00Z",
    "heartbeat_at": "2099-01-01T00:00:00Z",
    "ttl_seconds": 300,
}
payload.update(extra)
path.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
PY
}

run_projector() {
  python3 "$PROJECTOR" --once >/dev/null
}

case_from_output() {
  sed -n 's/^case_path=//p' "$1" | tail -1
}

fixture_from_output() {
  sed -n 's/^fixture_path=//p' "$1" | tail -1
}

# Missed running: appserver notLoaded without workspace hooks should produce an actionable fixture,
# but must not teach projector to turn weak appserver evidence blue.
write_ui_state '{"source":"state_projector","global_status":"done_verified","global_display_title":"DONE","lamp_status":"done_verified","counts":{"done_verified_visible":1},"diagnostics":{"projector_reason":["recent_done"],"fallback_reason":"none"},"runtime_candidates":[]}'
write_signals "[{\"signal_id\":\"sig-app-unknown\",\"source\":\"codex_appserver\",\"event_type\":\"unknown\",\"thread_id\":\"thread-app\",\"cwd\":\"$WORKSPACE\",\"occurred_at\":\"2099-01-01T00:00:00Z\",\"confidence\":0.0,\"source_quality\":\"codex_appserver_thread_list_ignored\",\"status_hint\":\"notLoaded\",\"evidence\":[\"thread/list:status=notLoaded\"]}]"
python3 "$CASE_TOOL" capture --expected running --note "other Codex workspace running but LuckyCat stayed DONE" --state-dir "$STATE_DIR" --workspace "$WORKSPACE" --skip-appserver >"$STATE_DIR/case.out"
CASE_PATH="$(case_from_output "$STATE_DIR/case.out")"
python3 - "$CASE_PATH" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1]))
assert payload["expected_status"] == "running", payload
assert payload["actual_status"] == "done", payload
fixture = payload["recommended_fixture"]
assert fixture["decision"] == "uncovered_active_suspect", payload
assert fixture["expected_projector_result"] == "idle_until_workspace_hooks_trusted", payload
assert "thread-app" not in json.dumps(payload), payload
PY
python3 "$CASE_TOOL" fixture --case "$CASE_PATH" >"$STATE_DIR/fixture.out"
FIXTURE_PATH="$(fixture_from_output "$STATE_DIR/fixture.out")"
python3 "$CASE_TOOL" verify-fixture --fixture "$FIXTURE_PATH" >/dev/null
python3 - "$FIXTURE_PATH" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1]))
assert payload["assertions"]["mismatch_class"] == "missed_running", payload
assert payload["assertions"]["weak_appserver_evidence_never_global_running"], payload
PY

# process_observer only remains diagnostic-only and produces a no-running assertion.
write_ui_state '{"source":"state_projector","global_status":"idle","global_display_title":"IDLE","lamp_status":"idle","counts":{},"diagnostics":{"projector_reason":["no_active_ui_scope"],"fallback_reason":"none"},"runtime_candidates":[]}'
write_signals '[{"signal_id":"sig-process","source":"process_observer","event_type":"observed_active","thread_id":"thread-proc","occurred_at":"2099-01-01T00:00:00Z","confidence":0.8,"source_quality":"process_observer","status_hint":"observed_active"}]'
python3 "$CASE_TOOL" capture --expected running --note "process observer cannot light main lamp" --state-dir "$STATE_DIR" --workspace "$WORKSPACE" --skip-appserver >"$STATE_DIR/process-case.out"
PROCESS_CASE_PATH="$(case_from_output "$STATE_DIR/process-case.out")"
python3 "$CASE_TOOL" fixture --case "$PROCESS_CASE_PATH" >"$STATE_DIR/process-fixture.out"
PROCESS_FIXTURE_PATH="$(fixture_from_output "$STATE_DIR/process-fixture.out")"
python3 "$CASE_TOOL" verify-fixture --fixture "$PROCESS_FIXTURE_PATH" >/dev/null
python3 - "$PROCESS_FIXTURE_PATH" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1]))
assert payload["assertions"]["process_observer_only_never_global_running"], payload
PY

# stale hook blocker does not keep the global lamp red.
rm -rf "$STATE_DIR/tasks" "$STATE_DIR/turn_bindings" "$STATE_DIR/thread_bindings"
mkdir -p "$STATE_DIR/tasks" "$STATE_DIR/turn_bindings" "$STATE_DIR/thread_bindings"
write_task "hook-block-old" "blocked" '{"reason":"needs_human_review","message":"old hook block","created_at":"2020-01-01T00:00:00Z","started_at":"2020-01-01T00:00:00Z","updated_at":"2020-01-01T00:00:00Z","heartbeat_at":"2020-01-01T00:00:00Z"}'
cat >"$STATE_DIR/turn_bindings/hook_unknown_turn-block-old.json" <<'JSON'
{"schema_version":"0.1","source_key":"hook:unknown:turn-block-old","canonical_identity":"turn:turn-block-old","task_id":"hook-block-old","turn_id":"turn-block-old","status":"released","last_signal_at":"2020-01-01T00:00:00Z","last_signal_event":"bridge_blocked","updated_at":"2020-01-01T00:00:00Z"}
JSON
write_signals '[{"signal_id":"sig-hook-block-old","source":"hook_bridge","event_type":"bridge_blocked","task_id":"hook-block-old","turn_id":"turn-block-old","occurred_at":"2020-01-01T00:00:00Z","confidence":0.95,"source_quality":"smoke","reason":"needs_human_review","evidence":["old-block"]}]'
run_projector
python3 - "$STATE_DIR/ui_state.json" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1]))
assert payload["global_status"] != "blocked", payload
assert payload["counts"]["blocked"] == 0, payload
PY

# explicit wrapper blocker still keeps the global lamp red.
rm -rf "$STATE_DIR/tasks" "$STATE_DIR/turn_bindings" "$STATE_DIR/thread_bindings"
mkdir -p "$STATE_DIR/tasks" "$STATE_DIR/turn_bindings" "$STATE_DIR/thread_bindings"
write_task "explicit-block" "blocked" '{"reason":"missing_input","message":"explicit block","evidence":"smoke"}'
write_signals '[{"signal_id":"sig-explicit-block","source":"explicit","event_type":"blocked","task_id":"explicit-block","occurred_at":"2099-01-01T00:00:00Z","confidence":1.0,"source_quality":"smoke","reason":"missing_input","evidence":["explicit-block"]}]'
run_projector
python3 - "$STATE_DIR/ui_state.json" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1]))
assert payload["global_status"] == "blocked", payload
assert payload["counts"]["blocked"] == 1, payload
PY

# old done_verified does not block a fresh hook running fixture.
rm -rf "$STATE_DIR/tasks" "$STATE_DIR/turn_bindings" "$STATE_DIR/thread_bindings"
mkdir -p "$STATE_DIR/tasks" "$STATE_DIR/turn_bindings" "$STATE_DIR/thread_bindings"
write_task "old-done" "done_verified" '{"done_at":"2020-01-01T00:00:00Z","verified_at":"2020-01-01T00:00:00Z"}'
write_task "fresh-run" "running" '{}'
cat >"$STATE_DIR/turn_bindings/hook_unknown_turn-fresh.json" <<'JSON'
{"schema_version":"0.1","source_key":"hook:unknown:turn-fresh","canonical_identity":"turn:turn-fresh","task_id":"fresh-run","turn_id":"turn-fresh","status":"active","last_signal_at":"2099-01-01T00:00:00Z","last_signal_event":"item_started","updated_at":"2099-01-01T00:00:00Z"}
JSON
write_signals '[{"signal_id":"sig-fresh-run","source":"codex_hook","event_type":"item_started","task_id":"fresh-run","turn_id":"turn-fresh","occurred_at":"2099-01-01T00:00:00Z","confidence":0.95,"source_quality":"codex_hook_event","status_hint":"active"}]'
run_projector
python3 - "$STATE_DIR/ui_state.json" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1]))
assert payload["global_status"] == "running", payload
assert payload["global_display_title"] == "RUNNING", payload
PY

echo "smoke_status_reflection_cases: ok"
