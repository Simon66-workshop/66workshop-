#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT_DIR/script/check_codex_thread_coverage.py"
INSTALL="$ROOT_DIR/script/install_hooks_for_workspace.sh"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-coverage-XXXXXX")"
WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-workspace-XXXXXX")"
trap 'rm -rf "$STATE_DIR" "$WORKSPACE"' EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_NORMALIZED_SIGNALS_PATH="$STATE_DIR/normalized_signals.jsonl"
mkdir -p "$STATE_DIR/turn_bindings" "$STATE_DIR/thread_bindings"

write_signals() {
  python3 - "$STATE_DIR/normalized_signals.jsonl" "$1" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
payload = json.loads(sys.argv[2])
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text("\n".join(json.dumps(item, sort_keys=True) for item in payload) + "\n", encoding="utf-8")
PY
}

run_json() {
  python3 "$CHECK" --json --skip-appserver --state-dir "$STATE_DIR" --signals-path "$STATE_DIR/normalized_signals.jsonl" "$@"
}

write_signals "[{\"signal_id\":\"sig-hook\",\"source\":\"codex_hook\",\"event_type\":\"item_started\",\"thread_id\":\"thread-hook\",\"turn_id\":\"turn-hook\",\"cwd\":\"$WORKSPACE\",\"occurred_at\":\"2099-01-01T00:00:00Z\",\"confidence\":0.95,\"source_quality\":\"codex_hook_event\",\"status_hint\":\"active\"}]"
run_json --workspace "$WORKSPACE" >"$STATE_DIR/hook.json"
python3 - "$STATE_DIR/hook.json" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1]))
assert payload["summary"]["covered_running"] == 1, payload
PY

write_signals '[{"signal_id":"sig-hook-no-cwd","source":"codex_hook","event_type":"item_started","thread_id":"thread-hook-no-cwd","turn_id":"turn-hook-no-cwd","occurred_at":"2099-01-01T00:00:00Z","confidence":0.95,"source_quality":"codex_hook_event","status_hint":"active"}]'
run_json --workspace "$WORKSPACE" >"$STATE_DIR/hook-no-cwd.json"
python3 - "$STATE_DIR/hook-no-cwd.json" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1]))
assert payload["summary"]["covered_running"] == 0, payload
assert payload["summary"]["uncovered_active_suspects"] >= 1, payload
PY

write_signals '[{"signal_id":"sig-app-unknown","source":"codex_appserver","event_type":"unknown","thread_id":"thread-app","occurred_at":"2099-01-01T00:00:00Z","confidence":0.0,"source_quality":"codex_appserver_thread_list_ignored","status_hint":"notLoaded","evidence":["thread/list:status=notLoaded"]}]'
run_json --workspace "$WORKSPACE" >"$STATE_DIR/unknown.json"
python3 - "$STATE_DIR/unknown.json" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1]))
assert payload["summary"]["uncovered_active_suspects"] >= 1, payload
PY
run_json --workspace "$WORKSPACE" --write-recommended-fixtures --fixture-output-dir "$STATE_DIR/fixtures" >"$STATE_DIR/unknown-fixture.json"
python3 - "$STATE_DIR/unknown-fixture.json" "$STATE_DIR/fixtures" <<'PY'
import json, sys
from pathlib import Path
payload = json.load(open(sys.argv[1]))
written = payload.get("written_recommended_fixtures") or []
assert written, payload
fixture = json.load(open(written[0]))
assert fixture["assertions"]["mismatch_class"] == "missed_running", fixture
assert fixture["assertions"]["weak_appserver_evidence_never_global_running"], fixture
assert Path(written[0]).is_relative_to(Path(sys.argv[2])) if hasattr(Path(written[0]), "is_relative_to") else str(written[0]).startswith(str(sys.argv[2])), written
PY

write_signals '[{"signal_id":"sig-process","source":"process_observer","event_type":"observed_active","thread_id":"thread-proc","occurred_at":"2099-01-01T00:00:00Z","confidence":0.8,"source_quality":"process_observer","status_hint":"observed_active"}]'
run_json --workspace "$WORKSPACE" >"$STATE_DIR/process.json"
python3 - "$STATE_DIR/process.json" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1]))
assert payload["summary"]["diagnostic_only"] >= 1, payload
assert payload["summary"]["covered_running"] == 0, payload
PY

write_signals '[{"signal_id":"sig-private","source":"codex_private_probe","event_type":"private_active","occurred_at":"2099-01-01T00:00:00Z","confidence":0.9,"source_quality":"global_private_metadata","status_hint":"active"}]'
run_json --no-default-workspace >"$STATE_DIR/private.json"
python3 - "$STATE_DIR/private.json" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1]))
assert payload["summary"]["diagnostic_only"] >= 1, payload
assert payload["threads"][0]["workspace"] == "unknown", payload
PY

write_signals '[{"signal_id":"sig-app-active","source":"codex_appserver","event_type":"turn_started","thread_id":"thread-app-active","occurred_at":"2099-01-01T00:00:00Z","confidence":0.82,"source_quality":"codex_appserver_thread_list_recent_activity","status_hint":"active","evidence":["thread/list:updatedAt advanced"],"appserver_activity_evidence":["thread/list:updatedAt advanced"]}]'
run_json --workspace "$WORKSPACE" >"$STATE_DIR/app-active.json"
python3 - "$STATE_DIR/app-active.json" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1]))
assert payload["summary"]["covered_running"] == 1, payload
PY

write_signals '[{"signal_id":"sig-stale","source":"codex_hook","event_type":"item_started","thread_id":"thread-stale","turn_id":"turn-stale","occurred_at":"2020-01-01T00:00:00Z","confidence":0.95,"source_quality":"codex_hook_event"}]'
run_json --workspace "$WORKSPACE" >"$STATE_DIR/stale.json"
python3 - "$STATE_DIR/stale.json" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1]))
assert payload["summary"]["stale"] >= 1, payload
PY

# A workspace missing hooks is a coverage debt, not proof that an old or
# signal-less binding is currently active. Do not inflate active-suspect counts
# from historical bindings.
python3 - "$CHECK" <<'PY'
import importlib.util
import sys
from pathlib import Path

check = Path(sys.argv[1])
sys.path.insert(0, str(check.parent))
spec = importlib.util.spec_from_file_location("coverage_check", check)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
result = module.classify_thread(
    {"signals": [], "workspace": "/tmp/missing-hooks", "workspace_source": "default", "appserver_status": "unknown"},
    {"hook_status": "missing"},
    now_ts=1_000.0,
    ttl=30.0,
)
assert result["decision"] == "diagnostic_only", result
assert result["reason"] == "no_thread_signal", result
PY

"$INSTALL" "$WORKSPACE" >/dev/null
python3 "$CHECK" --json --skip-appserver --state-dir "$STATE_DIR" --signals-path "$STATE_DIR/normalized_signals.jsonl" --workspace "$WORKSPACE" >"$STATE_DIR/installed.json"
python3 - "$STATE_DIR/installed.json" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1]))
workspace = next(iter(payload["workspaces"].values()))
assert workspace["hook_status"] == "ok", payload
assert payload["status"] == "awaiting_next_hook_event", payload
assert payload["summary"]["awaiting_next_hook_event"] >= 1, payload
assert payload["threads"][0]["post_trust_state"] == "awaiting_next_hook_event", payload
assert payload["threads"][0]["ui_effect"] == "none", payload
assert payload["threads"][0]["next_action"], payload
PY

echo "smoke_codex_thread_coverage: ok"
