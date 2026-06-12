#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCHER="$ROOT_DIR/script/appserver_thread_watcher.py"
PROJECTOR="$ROOT_DIR/script/state_projector.py"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-appserver-watch-XXXXXX")"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_UI_STATE_PATH="$STATE_DIR/ui_state.json"
export TASKLIGHT_STATE_PROJECTOR_HEALTH_PATH="$STATE_DIR/state_projector_health.json"
export TASKLIGHT_NORMALIZED_SIGNALS_PATH="$STATE_DIR/normalized_signals.jsonl"
export TASKLIGHT_APPSERVER_THREAD_WATCHER_STATE_PATH="$STATE_DIR/appserver_thread_watcher_state.json"
export TASKLIGHT_APPSERVER_THREAD_WATCHER_HEALTH_PATH="$STATE_DIR/appserver_thread_watcher_health.json"
export TASKLIGHT_APPSERVER_THREAD_ACTIVE_TTL_SECONDS=12
export TASKLIGHT_APPSERVER_THREAD_COALESCE_SECONDS=2
export TASKLIGHT_APPSERVER_THREAD_OBSERVER_DISABLED=0

FIXTURE="$STATE_DIR/appserver_fixture.jsonl"
cat >"$FIXTURE" <<'EOF'
{"source":"codex_appserver","event_type":"unknown","thread_id":"thread-current","event_time":"2099-01-01T00:00:00Z","confidence":0.0,"thread_scoped":true,"turn_scoped":false,"source_quality":"codex_appserver_thread_list_ignored","status_hint":"notLoaded","evidence":["thread/list:status=notLoaded"],"conflicts":["thread_list_notLoaded"]}
{"source":"codex_appserver","event_type":"turn_started","thread_id":"thread-other","event_time":"2099-01-01T00:00:00Z","confidence":0.82,"thread_scoped":true,"turn_scoped":false,"source_quality":"codex_appserver_thread_list_active","status_hint":"active","evidence":["thread/list:status=active"],"appserver_activity_evidence":["thread/list:status=active"],"conflicts":[]}
EOF
export TASKLIGHT_APPSERVER_THREAD_WATCHER_FIXTURE="$FIXTURE"
export CODEX_THREAD_ID="thread-current"

python3 "$WATCHER" --once >/dev/null

python3 - "$STATE_DIR/normalized_signals.jsonl" <<'PY'
import json
import sys
from pathlib import Path
lines = [json.loads(line) for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line.strip()]
assert len(lines) == 2, lines
assert {line["thread_id"] for line in lines} == {"thread-current", "thread-other"}, lines
PY

python3 "$WATCHER" --once >/dev/null
python3 - "$STATE_DIR/normalized_signals.jsonl" <<'PY'
import json
import sys
from pathlib import Path
lines = [json.loads(line) for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line.strip()]
assert len(lines) == 2, lines
PY

python3 "$PROJECTOR" --once >/dev/null
python3 - "$STATE_DIR/ui_state.json" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["global_status"] == "running", payload
assert payload["counts"]["observed_active"] == 1, payload
assert payload["counts"]["appserver_active"] == 1, payload
assert any(item["observation_id"] == "appserver:thread-other" and item["display_scope"] == "observed_active_high_confidence" for item in payload["observations"]), payload
assert any(candidate["candidate_id"] == "thread:thread-other" and candidate["display_scope"] == "observed_active_high_confidence" for candidate in payload["runtime_candidates"]), payload
assert payload["diagnostics"]["appserver_thread_signal_status"] == "bus", payload
assert payload["diagnostics"]["appserver_thread_watcher_status"] == "ok", payload
PY

CHECK_OUTPUT="$("$ROOT_DIR/script/check_appserver_thread_watcher.sh")"
printf '%s\n' "$CHECK_OUTPUT" | grep -Eq "STATUS=(not_running|ok)"

echo "smoke_appserver_thread_watcher: ok"
