#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATOR="$ROOT_DIR/script/self-review/generate_scope.py"
RUNNER="$ROOT_DIR/script/self-review/run_self_review.py"

if [ "${TASKLIGHT_SELF_REVIEW_EVIDENCE_MODE:-0}" = "1" ]; then
  echo "TASKLIGHT_SELF_REVIEW_EVIDENCE_MODE=1"
  echo "STATUS=ok"
  exit 0
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-generate-scope.XXXXXX")"
SAMPLE_DIR="$TMP_ROOT/M3.4c-sample"
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

make_env() {
  local name="$1"
  export TASKLIGHT_SELF_REVIEW_GENERATE_FIXTURE_DIR="$TMP_ROOT/$name/generate"
  export TASKLIGHT_SELF_REVIEW_FIXTURE_DIR="$TMP_ROOT/$name/evidence"
  export TASKLIGHT_SELF_REVIEW_REPORT_ROOT="$TMP_ROOT/$name/reports"
  mkdir -p "$TASKLIGHT_SELF_REVIEW_GENERATE_FIXTURE_DIR" "$TASKLIGHT_SELF_REVIEW_FIXTURE_DIR" "$TASKLIGHT_SELF_REVIEW_REPORT_ROOT"
}

write_generate_fixture() {
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
payload = {
    "branch": "scope-smoke",
    "head": "scope123",
    "staged_files": json.loads(sys.argv[2]),
    "unstaged_files": json.loads(sys.argv[3]),
    "untracked_files": json.loads(sys.argv[4]),
    "files": json.loads(sys.argv[5]),
}
root.mkdir(parents=True, exist_ok=True)
(root / "generate-scope-fixture.json").write_text(json.dumps(payload, ensure_ascii=True, indent=2, sort_keys=True), encoding="utf-8")
PY
}

write_review_fixture() {
  local fixture_dir="$1"
  local check_all_exit_code="${2:-0}"
  python3 - "$fixture_dir" "$check_all_exit_code" <<'PY'
import json
import sys
from pathlib import Path

fixture_dir = Path(sys.argv[1])
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
            "included_paths": ["script/self-review/", "config/self-review/", "docs/self-review/", "script/smoke_self_review.sh", "script/smoke_self_review_scope.sh", "script/smoke_self_review_generate_scope.sh"],
            "excluded_paths": ["dist/", "mac/66TaskLight/.build/", "__pycache__/"],
            "in_scope_changed_files": ["script/self-review/run_self_review.py"],
            "out_of_scope_dirty_files": ["script/check_codex_hooks_trust.py"],
            "out_of_scope_risk_classes": {"ordinary": [], "launch_trust": ["script/check_codex_hooks_trust.py"], "auth_secret": [], "unknown": []},
            "scope_decision": "NEEDS_HUMAN_REVIEW",
            "scope_reason": "Auto-generated scope candidate. Review manually before use."
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
fixture_dir.mkdir(parents=True, exist_ok=True)
(fixture_dir / "command-results.json").write_text(json.dumps(payload, ensure_ascii=True, indent=2, sort_keys=True), encoding="utf-8")
PY
}

write_baseline_override() {
  python3 - "$1" "$2" "$3" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
changed = json.loads(sys.argv[2])
staged = json.loads(sys.argv[3])
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
root.mkdir(parents=True, exist_ok=True)
(root / "baseline-overrides.json").write_text(json.dumps(payload, ensure_ascii=True, indent=2, sort_keys=True), encoding="utf-8")
PY
}

run_generate() {
  local task_id="$1"
  shift
  python3 "$GENERATOR" --task-id "$task_id" --task-type state_projector --task-type hook_bridge "$@" >"$TMP_ROOT/$task_id.generate.out"
}

run_review() {
  local task_id="$1"
  shift
  python3 "$RUNNER" --task-id "$task_id" --task-type state_projector --task-type hook_bridge --mode final "$@" >"$TMP_ROOT/$task_id.review.out"
}

assert_json_field() {
  python3 - "$1" "$2" "$3" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
expr = sys.argv[2]
expected = sys.argv[3]
value = eval(expr, {"payload": payload})
if str(value) != expected:
    raise SystemExit(f"expected {expected}, got {value}")
PY
}

assert_json_expr_true() {
  python3 - "$1" "$2" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
expr = sys.argv[2]
if not eval(expr, {"payload": payload}):
    raise SystemExit(f"expression failed: {expr}")
PY
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  grep -q "$needle" "$path"
}

assert_file_not_contains() {
  local path="$1"
  local needle="$2"
  if grep -q "$needle" "$path"; then
    echo "unexpected match in $path: $needle" >&2
    exit 1
  fi
}

# 1. self-review file changes -> in-scope, recommended include expands to self-review roots.
make_env case1
write_generate_fixture "$TASKLIGHT_SELF_REVIEW_GENERATE_FIXTURE_DIR" \
  '["script/self-review/run_self_review.py"]' \
  '["config/self-review/scoring-rubrics.json"]' \
  '[]' \
  '{"script/self-review/run_self_review.py":"print(\"alpha\")","config/self-review/scoring-rubrics.json":"{\"weights\":{}}"}'
run_generate M3.4c-case1 --output-dir "$TMP_ROOT/case1/report"
assert_json_expr_true "$TMP_ROOT/case1/report/scope-candidate.json" '"script/self-review/run_self_review.py" in payload["classification"]["in_scope_candidates"]'
assert_json_expr_true "$TMP_ROOT/case1/report/scope-candidate.json" '"config/self-review/scoring-rubrics.json" in payload["classification"]["in_scope_candidates"]'
assert_json_expr_true "$TMP_ROOT/case1/report/scope-candidate.json" '"script/self-review/" in payload["recommendation"]["include"]'
assert_json_expr_true "$TMP_ROOT/case1/report/scope-candidate.json" '"config/self-review/" in payload["recommendation"]["include"]'

# 2. build artifact -> excluded, never included.
make_env case2
write_generate_fixture "$TASKLIGHT_SELF_REVIEW_GENERATE_FIXTURE_DIR" \
  '["dist/app.zip"]' \
  '["mac/66TaskLight/.build/debug/app.o"]' \
  '[]' \
  '{"dist/app.zip":"zip","mac/66TaskLight/.build/debug/app.o":"o"}'
run_generate M3.4c-case2 --output-dir "$TMP_ROOT/case2/report"
assert_json_expr_true "$TMP_ROOT/case2/report/scope-candidate.json" '"dist/app.zip" in payload["classification"]["build_artifacts"]'
assert_json_expr_true "$TMP_ROOT/case2/report/scope-candidate.json" '"mac/66TaskLight/.build/debug/app.o" in payload["classification"]["build_artifacts"]'
assert_json_expr_true "$TMP_ROOT/case2/report/scope-candidate.json" '"dist/" in payload["recommendation"]["exclude"]'
assert_json_expr_true "$TMP_ROOT/case2/report/scope-candidate.json" '"mac/66TaskLight/.build/" in payload["recommendation"]["exclude"]'
assert_json_expr_true "$TMP_ROOT/case2/report/scope-candidate.json" '"dist/app.zip" not in payload["recommendation"]["include"]'
assert_json_expr_true "$TMP_ROOT/case2/report/scope-candidate.json" '"mac/66TaskLight/.build/debug/app.o" not in payload["recommendation"]["include"]'

# 3. launch/trust files -> NEEDS_HUMAN_REVIEW.
make_env case3
write_generate_fixture "$TASKLIGHT_SELF_REVIEW_GENERATE_FIXTURE_DIR" \
  '["script/check_codex_hooks_trust.py"]' \
  '[".codex/hooks.json"]' \
  '[]' \
  '{"script/check_codex_hooks_trust.py":"launch trust",".codex/hooks.json":"{}"}'
run_generate M3.4c-case3 --output-dir "$TMP_ROOT/case3/report"
assert_json_expr_true "$TMP_ROOT/case3/report/scope-candidate.json" 'len(payload["classification"]["risky_launch_trust"]) > 0'
assert_json_field "$TMP_ROOT/case3/report/scope-candidate.json" 'payload["risk_summary"]["recommended_decision"]' "NEEDS_HUMAN_REVIEW"

# 4. auth/secret files -> REJECT, secret value must not leak.
make_env case4
write_generate_fixture "$TASKLIGHT_SELF_REVIEW_GENERATE_FIXTURE_DIR" \
  '[".env"]' \
  '["config/secret-token.txt"]' \
  '[]' \
  '{".env":"not used","config/secret-token.txt":"secret marker","notes/plain.txt":"OPENAI_API_KEY=super-secret-token"}'
run_generate M3.4c-case4 --output-dir "$TMP_ROOT/case4/report"
assert_json_expr_true "$TMP_ROOT/case4/report/scope-candidate.json" 'len(payload["classification"]["risky_auth_secret"]) > 0'
assert_json_field "$TMP_ROOT/case4/report/scope-candidate.json" 'payload["risk_summary"]["recommended_decision"]' "REJECT"
assert_file_not_contains "$TMP_ROOT/case4/report/scope-candidate.json" "super-secret-token"

# 5. unknown dirty -> CONDITIONAL_PASS.
make_env case5
write_generate_fixture "$TASKLIGHT_SELF_REVIEW_GENERATE_FIXTURE_DIR" \
  '["random/unknown.txt"]' \
  '[]' \
  '[]' \
  '{"random/unknown.txt":"mystery"}'
run_generate M3.4c-case5 --output-dir "$TMP_ROOT/case5/report"
assert_json_expr_true "$TMP_ROOT/case5/report/scope-candidate.json" '"random/unknown.txt" in payload["classification"]["unknown"]'
assert_json_field "$TMP_ROOT/case5/report/scope-candidate.json" 'payload["risk_summary"]["recommended_decision"]' "CONDITIONAL_PASS"

# 6. --write-scope-file -> self-review-scope.json exists and is readable by run_self_review.
make_env case6
write_generate_fixture "$TASKLIGHT_SELF_REVIEW_GENERATE_FIXTURE_DIR" \
  '["script/self-review/run_self_review.py"]' \
  '["config/self-review/scoring-rubrics.json"]' \
  '[]' \
  '{"script/self-review/run_self_review.py":"print(\"alpha\")","config/self-review/scoring-rubrics.json":"{\"weights\":{}}"}'
rm -rf "$SAMPLE_DIR"
mkdir -p "$SAMPLE_DIR"
python3 "$GENERATOR" --task-id M3.4c-sample --task-type state_projector --task-type hook_bridge --output-dir "$SAMPLE_DIR" --write-scope-file --scope-name self-review-scope >"$TMP_ROOT/case6.generate.out"
assert_file_contains "$SAMPLE_DIR/self-review-scope.json" '"include"'
assert_file_contains "$SAMPLE_DIR/scope-candidate.md" 'Suggested Command'

# 7. chained generate -> scoped review.
make_env case7
write_generate_fixture "$TASKLIGHT_SELF_REVIEW_GENERATE_FIXTURE_DIR" \
  '["script/self-review/run_self_review.py"]' \
  '["random/unknown.txt"]' \
  '[]' \
  '{"script/self-review/run_self_review.py":"print(\"alpha\")","random/unknown.txt":"mystery"}'
write_review_fixture "$TASKLIGHT_SELF_REVIEW_FIXTURE_DIR" 0
write_baseline_override "$TASKLIGHT_SELF_REVIEW_FIXTURE_DIR" \
  '["script/self-review/run_self_review.py","random/unknown.txt"]' \
  '["script/self-review/run_self_review.py"]'
python3 "$GENERATOR" --task-id smoke-scope --task-type state_projector --task-type hook_bridge --output-dir "$TMP_ROOT/case7/generate" --write-scope-file >"$TMP_ROOT/case7.generate.out"
python3 "$RUNNER" --task-id smoke-scope --task-type state_projector --task-type hook_bridge --scope-file "$TMP_ROOT/case7/generate/self-review-scope.json" --evidence-profile fast --mode final >"$TMP_ROOT/case7.review.out"
assert_file_contains "$TMP_ROOT/case7/generate/self-review-scope.json" '"include"'
assert_file_contains "$TASKLIGHT_SELF_REVIEW_REPORT_ROOT/smoke-scope/final-review.md" 'scope_summary_path'
assert_file_contains "$TASKLIGHT_SELF_REVIEW_REPORT_ROOT/smoke-scope/scope-summary.json" '"scope_decision"'

echo "smoke_self_review_generate_scope: ok"
