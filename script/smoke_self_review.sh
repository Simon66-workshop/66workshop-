#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT_DIR/script/self-review/run_self_review.py"

if [ "${TASKLIGHT_SELF_REVIEW_EVIDENCE_MODE:-0}" = "1" ]; then
  echo "TASKLIGHT_SELF_REVIEW_EVIDENCE_MODE=1"
  echo "STATUS=ok"
  exit 0
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-self-review-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

make_state_env() {
  local name="$1"
  export TASKLIGHT_STATE_DIR="$TMP_ROOT/$name/state"
  export TASKLIGHT_UI_STATE_PATH="$TASKLIGHT_STATE_DIR/ui_state.json"
  export TASKLIGHT_NORMALIZED_SIGNALS_PATH="$TASKLIGHT_STATE_DIR/normalized_signals.jsonl"
  export TASKLIGHT_SELF_REVIEW_FIXTURE_DIR="$TMP_ROOT/$name/fixture"
  export TASKLIGHT_SELF_REVIEW_REPORT_ROOT="$TMP_ROOT/$name/reports"
  mkdir -p "$TASKLIGHT_STATE_DIR/tasks" "$TASKLIGHT_SELF_REVIEW_FIXTURE_DIR"
}

write_ui_state() {
  python3 - "$TASKLIGHT_UI_STATE_PATH" "$1" <<'PY'
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
  python3 - "$TASKLIGHT_NORMALIZED_SIGNALS_PATH" "$1" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
records = json.loads(sys.argv[2])
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text("\n".join(json.dumps(item, sort_keys=True) for item in records) + "\n", encoding="utf-8")
PY
}

write_task() {
  python3 - "$TASKLIGHT_STATE_DIR/tasks/$1.json" "$1" "$2" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
payload = {
    "schema_version": 3,
    "task_id": sys.argv[2],
    "status": sys.argv[3],
    "raw_status": sys.argv[3],
    "effective_status": sys.argv[3],
    "title": sys.argv[2],
    "slug": sys.argv[2],
    "phase": "smoke",
    "progress": 1.0,
    "created_at": "2099-01-01T00:00:00Z",
    "updated_at": "2099-01-01T00:00:00Z",
    "heartbeat_at": "2099-01-01T00:00:00Z"
}
path.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
PY
}

write_fixture_commands() {
  python3 - "$TASKLIGHT_SELF_REVIEW_FIXTURE_DIR/command-results.json" "$1" <<'PY'
import json
import sys
from pathlib import Path
mode = sys.argv[2]
base = {
    "check_all": {"exit_code": 0, "status_line": "check_all: ok", "key_values": {}},
    "check_state_projector": {"exit_code": 0, "status_line": "STATUS=ok", "key_values": {"STATUS": "ok", "writer_status": "ok"}},
    "check_hook_bridge_launch_agent": {"exit_code": 0, "status_line": "STATUS=ok", "key_values": {"STATUS": "ok"}},
    "check_ui_client": {"exit_code": 0, "status_line": "STATUS=ok", "key_values": {"STATUS": "ok"}},
    "smoke_turn_runtime_arbiter": {"exit_code": 0, "status_line": "smoke_turn_runtime_arbiter: ok", "key_values": {}},
    "smoke_state_projector": {"exit_code": 0, "status_line": "smoke_state_projector: ok", "key_values": {}},
    "smoke_hook_signal_bridge": {"exit_code": 0, "status_line": "smoke_hook_signal_bridge: ok", "key_values": {}},
    "smoke_appserver_thread_watcher": {"exit_code": 0, "status_line": "smoke_appserver_thread_watcher: ok", "key_values": {}},
}
if mode == "missing_evidence":
    base["check_state_projector"] = {"exit_code": 127, "status_line": "command missing", "key_values": {}}
if mode == "check_all_fail":
    base["check_all"] = {"exit_code": 1, "status_line": "check_all: failed", "key_values": {}}
Path(sys.argv[1]).write_text(json.dumps(base, sort_keys=True), encoding="utf-8")
PY
}

write_baseline_override() {
  python3 - "$TASKLIGHT_SELF_REVIEW_FIXTURE_DIR/baseline-overrides.json" <<'PY'
import json
import sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({"git": {"changed_files": [], "staged_files": [], "status_entries": []}}, sort_keys=True), encoding="utf-8")
PY
}

run_review() {
  local task_id="$1"
  python3 "$RUNNER" --task-id "$task_id" --task-type state_projector --task-type hook_bridge --evidence-profile full --mode final >"$TMP_ROOT/$task_id.out"
}

assert_json_field() {
  python3 - "$1" "$2" "$3" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
expr = sys.argv[2]
expected = sys.argv[3]
value = eval(expr, {"payload": payload})
if str(value) != expected:
    raise SystemExit(f"expected {expected}, got {value}")
PY
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  grep -q "$needle" "$path"
}

# 1. missing evidence -> REJECT
make_state_env missing-evidence
write_fixture_commands missing_evidence
write_baseline_override
write_ui_state '{"source":"state_projector","projector_version":"M3.3","global_status":"idle","global_display_title":"IDLE","lamp_status":"idle","counts":{"pending_verify_count":0},"diagnostics":{"writer_status":"ok","projector_reason":["idle"]}}'
write_signals '[{"signal_id":"sig-1","source":"codex_hook","event_type":"item_started"}]'
run_review SMOKE-MISSING-EVIDENCE
assert_json_field "$TMP_ROOT/SMOKE-MISSING-EVIDENCE.out" 'payload["decision"]' "REJECT"

# 2. check_all fail fixture -> REJECT
make_state_env check-all-fail
write_fixture_commands check_all_fail
write_baseline_override
write_ui_state '{"source":"state_projector","projector_version":"M3.3","global_status":"idle","global_display_title":"IDLE","lamp_status":"idle","counts":{"pending_verify_count":0},"diagnostics":{"writer_status":"ok","projector_reason":["idle"]}}'
write_signals '[{"signal_id":"sig-2","source":"codex_hook","event_type":"item_started"}]'
run_review SMOKE-CHECK-ALL-FAIL
assert_json_field "$TMP_ROOT/SMOKE-CHECK-ALL-FAIL.out" 'payload["decision"]' "REJECT"

# 3. process-only running fixture -> false_blue_running
make_state_env process-only-running
write_fixture_commands clean
write_baseline_override
write_ui_state '{"source":"state_projector","projector_version":"M3.3","global_status":"running","global_display_title":"RUNNING","lamp_status":"running","counts":{"pending_verify_count":0},"diagnostics":{"writer_status":"ok","projector_reason":["active_execution"]}}'
write_signals '[{"signal_id":"sig-3","source":"process_observer","event_type":"observed_active"}]'
run_review SMOKE-PROCESS-ONLY-RUNNING
assert_json_field "$TMP_ROOT/SMOKE-PROCESS-ONLY-RUNNING.out" 'payload["decision"]' "REJECT"
assert_file_contains "$TMP_ROOT/process-only-running/reports/SMOKE-PROCESS-ONLY-RUNNING/reflection.json" 'false_blue_running'

# 4. stop->done fixture -> PASS/CONDITIONAL_PASS
make_state_env stop-pending
write_fixture_commands clean
write_baseline_override
write_task stop-task done_unverified
write_ui_state '{"source":"state_projector","projector_version":"M3.3","global_status":"pending","global_display_title":"PENDING","lamp_status":"pending","counts":{"pending_verify_count":1},"diagnostics":{"writer_status":"ok","projector_reason":["pending_verify"]}}'
write_signals '[{"signal_id":"sig-4","source":"codex_hook","event_type":"stop"}]'
run_review SMOKE-STOP-PENDING
python3 - "$TMP_ROOT/SMOKE-STOP-PENDING.out" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1]))
assert payload["decision"] in {"PASS", "CONDITIONAL_PASS"}, payload
PY

# 5. fake green fixture -> REJECT
make_state_env fake-green
write_fixture_commands clean
write_baseline_override
write_task fake-green done_unverified
write_ui_state '{"source":"state_projector","projector_version":"M3.3","global_status":"done_verified","global_display_title":"DONE","lamp_status":"done_verified","counts":{"pending_verify_count":1},"diagnostics":{"writer_status":"ok","projector_reason":["recent_done"]}}'
write_signals '[{"signal_id":"sig-5","source":"codex_hook","event_type":"stop"}]'
run_review SMOKE-FAKE-GREEN
assert_json_field "$TMP_ROOT/SMOKE-FAKE-GREEN.out" 'payload["decision"]' "REJECT"
assert_file_contains "$TMP_ROOT/fake-green/reports/SMOKE-FAKE-GREEN/reflection.json" 'false_green_done'

# 6. final report generated
make_state_env final-report
write_fixture_commands clean
write_baseline_override
write_ui_state '{"source":"state_projector","projector_version":"M3.3","global_status":"running","global_display_title":"RUNNING","lamp_status":"running","counts":{"pending_verify_count":0},"diagnostics":{"writer_status":"ok","projector_reason":["active_execution"]}}'
write_signals '[{"signal_id":"sig-6","source":"codex_hook","event_type":"item_started"}]'
run_review SMOKE-FINAL-REPORT
assert_json_field "$TMP_ROOT/SMOKE-FINAL-REPORT.out" 'payload["decision"]' "PASS"
test -f "$TMP_ROOT/final-report/reports/SMOKE-FINAL-REPORT/final-review.md"

echo "smoke_self_review: ok"
