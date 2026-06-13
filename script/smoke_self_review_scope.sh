#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT_DIR/script/self-review/run_self_review.py"

if [ "${TASKLIGHT_SELF_REVIEW_EVIDENCE_MODE:-0}" = "1" ]; then
  echo "TASKLIGHT_SELF_REVIEW_EVIDENCE_MODE=1"
  echo "STATUS=ok"
  exit 0
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-self-review-scope.XXXXXX")"
SMOKE_SOURCE_DIR="$TMP_ROOT/source-fixtures"
REPO_SCOPE_DIR="$ROOT_DIR/script/.scope-smoke-fixtures"
REPO_SCOPE_IN_DIR="$ROOT_DIR/script/self-review/.scope-smoke-fixtures"
trap 'rm -rf "$TMP_ROOT" "$REPO_SCOPE_IN_DIR" "$REPO_SCOPE_DIR"' EXIT INT TERM

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

write_fixture_commands() {
  local check_all_exit_code="${1:-0}"
  python3 - "$TASKLIGHT_SELF_REVIEW_FIXTURE_DIR/command-results.json" "$check_all_exit_code" <<'PY'
import json
import sys
from pathlib import Path
check_all_exit_code = int(sys.argv[2])
payload = {
    "check_all": {"exit_code": check_all_exit_code, "status_line": "check_all: ok" if check_all_exit_code == 0 else "check_all: failed", "key_values": {}},
    "check_state_projector": {"exit_code": 0, "status_line": "STATUS=ok", "key_values": {"STATUS": "ok", "writer_status": "ok"}},
    "check_hook_bridge_launch_agent": {"exit_code": 0, "status_line": "STATUS=ok", "key_values": {"STATUS": "ok"}},
    "check_ui_client": {"exit_code": 0, "status_line": "STATUS=ok", "key_values": {"STATUS": "ok"}},
    "smoke_turn_runtime_arbiter": {"exit_code": 0, "status_line": "smoke_turn_runtime_arbiter: ok", "key_values": {}},
    "smoke_state_projector": {"exit_code": 0, "status_line": "smoke_state_projector: ok", "key_values": {}},
    "smoke_hook_signal_bridge": {"exit_code": 0, "status_line": "smoke_hook_signal_bridge: ok", "key_values": {}},
    "smoke_appserver_thread_watcher": {"exit_code": 0, "status_line": "smoke_appserver_thread_watcher: ok", "key_values": {}},
    "py_compile_self_review": {"exit_code": 0, "status_line": "py_compile_self_review: ok", "key_values": {"compiled_files": ["script/self-review/*.py", "script/self-review/auditors/*.py"]}},
    "basic_git_scope_audit": {
        "exit_code": 0,
        "status_line": "basic_git_scope_audit: ok",
        "key_values": {
            "review_scope": "scoped",
            "included_paths": ["script/self-review/", "config/self-review/", "docs/self-review/", "script/smoke_self_review.sh"],
            "excluded_paths": ["dist/", "mac/66TaskLight/.build/", "__pycache__/"],
            "in_scope_changed_files": ["script/self-review/run_self_review.py"],
            "out_of_scope_dirty_files": ["script/check_codex_hooks_trust.py"],
            "out_of_scope_risk_classes": {"ordinary": [], "launch_trust": ["script/check_codex_hooks_trust.py"], "auth_secret": [], "unknown": []},
            "scope_decision": "NEEDS_HUMAN_REVIEW",
            "scope_reason": "Limit review to Self-Review Arbiter Phase 1 files."
        }
    },
    "release_readiness": {
        "exit_code": 0,
        "status_line": "release_readiness_audit: ok",
        "key_values": {
            "staged_build_artifacts": [],
            "ignored_paths": [],
            "docs_assets_ignored": False,
            "appassets_ignored": False,
            "release_ready": True
        }
    }
}
Path(sys.argv[1]).write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
PY
}

write_baseline_override() {
  python3 - "$TASKLIGHT_SELF_REVIEW_FIXTURE_DIR/baseline-overrides.json" "$1" "$2" <<'PY'
import json
import sys
from pathlib import Path
changed = [item for item in sys.argv[2].split(":") if item]
staged = [item for item in sys.argv[3].split(":") if item]
status_entries = [{"status": ("M " if path in staged else " M"), "path": path} for path in changed]
payload = {
    "git": {
        "branch": "scope-smoke",
        "head": "scope123",
        "changed_files": changed,
        "staged_files": staged,
        "status_entries": status_entries,
    }
}
Path(sys.argv[1]).write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
PY
}

write_scope_file() {
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import json
import sys
from pathlib import Path
task_id = sys.argv[2]
include = [item for item in sys.argv[3].split(":") if item]
exclude = [item for item in sys.argv[4].split(":") if item]
reason = sys.argv[5]
payload = {"task_id": task_id, "include": include, "exclude": exclude, "reason": reason}
Path(sys.argv[1]).write_text(json.dumps(payload, ensure_ascii=True, indent=2), encoding="utf-8")
PY
}

run_review() {
  local task_id="$1"
  shift
  python3 "$RUNNER" --task-id "$task_id" --task-type state_projector --task-type hook_bridge --mode final "$@" >"$TMP_ROOT/$task_id.out"
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

mkdir -p "$SMOKE_SOURCE_DIR" "$REPO_SCOPE_DIR" "$REPO_SCOPE_IN_DIR"
cat >"$SMOKE_SOURCE_DIR/ordinary.txt" <<'EOF'
ordinary dirty file
EOF
cat >"$SMOKE_SOURCE_DIR/launch_agent_note.txt" <<'EOF'
launch review note only
EOF
cat >"$SMOKE_SOURCE_DIR/auth_secret_note.py" <<'EOF'
AUTH_REF = "~/.codex/auth.json"
EOF
python3 - "$SMOKE_SOURCE_DIR/in_scope_forbidden.py" <<'PY'
import sys
from pathlib import Path

line_part_a = 'subprocess.run(["git", '
line_part_b = '"push"], check=False)'
line_parts = [line_part_a, line_part_b]
code = "\n".join(["import subprocess", "".join(line_parts), ""])
Path(sys.argv[1]).write_text(code, encoding="utf-8")
PY
cp "$SMOKE_SOURCE_DIR/ordinary.txt" "$REPO_SCOPE_DIR/ordinary.txt"
cp "$SMOKE_SOURCE_DIR/launch_agent_note.txt" "$REPO_SCOPE_DIR/launch_agent_note.txt"
cp "$SMOKE_SOURCE_DIR/auth_secret_note.py" "$REPO_SCOPE_DIR/auth_secret_note.py"
cp "$SMOKE_SOURCE_DIR/in_scope_forbidden.py" "$REPO_SCOPE_IN_DIR/in_scope_forbidden.py"

COMMON_UI='{"source":"state_projector","projector_version":"M3.3","global_status":"running","global_display_title":"RUNNING","lamp_status":"running","counts":{"pending_verify_count":0},"diagnostics":{"writer_status":"ok","projector_reason":["active_execution"]}}'
COMMON_SIGNAL='[{"signal_id":"sig-scope","source":"codex_hook","event_type":"item_started"}]'

# 1. scope 内 clean + scope 外 unrelated dirty -> 不 REJECT
make_state_env scope-out-ordinary
write_fixture_commands
write_ui_state "$COMMON_UI"
write_signals "$COMMON_SIGNAL"
write_baseline_override "script/self-review/run_self_review.py:script/.scope-smoke-fixtures/ordinary.txt" ""
write_scope_file "$TMP_ROOT/scope-out-ordinary.json" "SCOPE-OUT-ORDINARY" "script/self-review/" "dist/:mac/66TaskLight/.build/:__pycache__/" "scope ordinary dirty"
run_review SCOPE-OUT-ORDINARY --scope-file "$TMP_ROOT/scope-out-ordinary.json"
assert_json_field "$TMP_ROOT/SCOPE-OUT-ORDINARY.out" 'payload["decision"]' "CONDITIONAL_PASS"
assert_file_contains "$TMP_ROOT/scope-out-ordinary/reports/SCOPE-OUT-ORDINARY/final-review.md" 'out_of_scope_dirty_files'
assert_file_contains "$TMP_ROOT/scope-out-ordinary/reports/SCOPE-OUT-ORDINARY/scope-summary.json" '"in_scope_changed_files"'
assert_json_field "$TMP_ROOT/scope-out-ordinary/reports/SCOPE-OUT-ORDINARY/scope-summary.json" 'len(payload["in_scope_changed_files"]) > 0' "True"
assert_json_field "$TMP_ROOT/scope-out-ordinary/reports/SCOPE-OUT-ORDINARY/scope-summary.json" 'len(payload["out_of_scope_dirty_files"]) > 0' "True"

# 1b. fast profile should skip check_all but keep scoped acceptance non-REJECT
make_state_env fast-profile
write_fixture_commands 1
write_ui_state "$COMMON_UI"
write_signals "$COMMON_SIGNAL"
write_baseline_override "script/self-review/run_self_review.py:script/.scope-smoke-fixtures/ordinary.txt" ""
write_scope_file "$TMP_ROOT/fast-profile.json" "FAST-PROFILE" "script/self-review/" "dist/:mac/66TaskLight/.build/:__pycache__/" "fast profile check"
run_review FAST-PROFILE --scope-file "$TMP_ROOT/fast-profile.json" --evidence-profile fast
assert_json_field "$TMP_ROOT/FAST-PROFILE.out" 'payload["evidence_profile"]' "fast"
assert_json_field "$TMP_ROOT/FAST-PROFILE.out" 'payload["decision"]' "CONDITIONAL_PASS"
assert_json_field "$TMP_ROOT/fast-profile/reports/FAST-PROFILE/evidence.json" 'payload["profile_summary"]["check_all_ran"]' "False"
assert_json_field "$TMP_ROOT/fast-profile/reports/FAST-PROFILE/evidence.json" 'payload["profile_summary"]["evidence_profile"]' "fast"

# 2. scope 内 forbidden file -> REJECT
make_state_env scope-in-forbidden
write_fixture_commands
write_ui_state "$COMMON_UI"
write_signals "$COMMON_SIGNAL"
write_baseline_override "script/self-review/.scope-smoke-fixtures/in_scope_forbidden.py" ""
write_scope_file "$TMP_ROOT/scope-in-forbidden.json" "SCOPE-IN-FORBIDDEN" "script/self-review/.scope-smoke-fixtures/" "" "scope forbidden"
run_review SCOPE-IN-FORBIDDEN --scope-file "$TMP_ROOT/scope-in-forbidden.json"
assert_json_field "$TMP_ROOT/SCOPE-IN-FORBIDDEN.out" 'payload["decision"]' "REJECT"

# 3. scope 外 auth/secret file -> REJECT
make_state_env scope-out-auth
write_fixture_commands
write_ui_state "$COMMON_UI"
write_signals "$COMMON_SIGNAL"
write_baseline_override "script/self-review/run_self_review.py:script/.scope-smoke-fixtures/auth_secret_note.py" ""
write_scope_file "$TMP_ROOT/scope-out-auth.json" "SCOPE-OUT-AUTH" "script/self-review/" "" "scope out auth"
run_review SCOPE-OUT-AUTH --scope-file "$TMP_ROOT/scope-out-auth.json"
assert_json_field "$TMP_ROOT/SCOPE-OUT-AUTH.out" 'payload["decision"]' "REJECT"

# 4. scope 外 launch/trust file -> NEEDS_HUMAN_REVIEW
make_state_env scope-out-launch
write_fixture_commands
write_ui_state "$COMMON_UI"
write_signals "$COMMON_SIGNAL"
write_baseline_override "script/self-review/run_self_review.py:script/.scope-smoke-fixtures/launch_agent_note.txt" ""
write_scope_file "$TMP_ROOT/scope-out-launch.json" "SCOPE-OUT-LAUNCH" "script/self-review/" "" "scope out launch"
run_review SCOPE-OUT-LAUNCH --scope-file "$TMP_ROOT/scope-out-launch.json"
assert_json_field "$TMP_ROOT/SCOPE-OUT-LAUNCH.out" 'payload["decision"]' "NEEDS_HUMAN_REVIEW"

# 5. no scope file -> 仍按 whole working tree 审
make_state_env no-scope-whole-tree
write_fixture_commands
write_ui_state "$COMMON_UI"
write_signals "$COMMON_SIGNAL"
write_baseline_override "script/.scope-smoke-fixtures/launch_agent_note.txt" ""
run_review NO-SCOPE-WHOLE-TREE
assert_json_field "$TMP_ROOT/NO-SCOPE-WHOLE-TREE.out" 'payload["decision"]' "NEEDS_HUMAN_REVIEW"
assert_json_field "$TMP_ROOT/NO-SCOPE-WHOLE-TREE.out" 'payload["review_scope"]["mode"]' "whole_worktree"

# 6. full profile should keep current default behavior
make_state_env full-profile
write_fixture_commands
write_ui_state "$COMMON_UI"
write_signals "$COMMON_SIGNAL"
write_baseline_override "script/self-review/run_self_review.py:script/.scope-smoke-fixtures/ordinary.txt" ""
write_scope_file "$TMP_ROOT/full-profile.json" "FULL-PROFILE" "script/self-review/" "dist/:mac/66TaskLight/.build/:__pycache__/" "full profile check"
run_review FULL-PROFILE --scope-file "$TMP_ROOT/full-profile.json" --evidence-profile full
assert_json_field "$TMP_ROOT/FULL-PROFILE.out" 'payload["evidence_profile"]' "full"
assert_json_field "$TMP_ROOT/full-profile/reports/FULL-PROFILE/evidence.json" 'payload["profile_summary"]["check_all_ran"]' "True"

# 7. release profile should emit release readiness summary
make_state_env release-profile
write_fixture_commands
write_ui_state "$COMMON_UI"
write_signals "$COMMON_SIGNAL"
write_baseline_override "script/self-review/run_self_review.py:script/.scope-smoke-fixtures/ordinary.txt" ""
write_scope_file "$TMP_ROOT/release-profile.json" "RELEASE-PROFILE" "script/self-review/" "dist/:mac/66TaskLight/.build/:__pycache__/" "release profile check"
run_review RELEASE-PROFILE --scope-file "$TMP_ROOT/release-profile.json" --evidence-profile release
assert_json_field "$TMP_ROOT/RELEASE-PROFILE.out" 'payload["evidence_profile"]' "release"
assert_json_field "$TMP_ROOT/release-profile/reports/RELEASE-PROFILE/evidence.json" 'payload["profile_summary"]["release_readiness"]["release_ready"]' "True"
assert_file_contains "$TMP_ROOT/release-profile/reports/RELEASE-PROFILE/evidence.md" 'release_readiness'

# 8. final report generated
assert_file_contains "$TMP_ROOT/release-profile/reports/RELEASE-PROFILE/final-review.md" 'scope_summary_path'

echo "smoke_self_review_scope: ok"
