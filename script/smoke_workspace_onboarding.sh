#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-onboard-workspace-XXXXXX")"
STATE_DIR="$WORKSPACE/state"
trap 'rm -rf "$WORKSPACE"' EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_SIGNAL_SPOOL_DIR="$STATE_DIR/signals"
export TASKLIGHT_NORMALIZED_SIGNALS_PATH="$STATE_DIR/normalized_signals.jsonl"

touch "$WORKSPACE/AGENTS.md"

python3 "$ROOT_DIR/script/onboard_workspace_for_monitoring.py" \
  --json \
  --skip-appserver \
  --workspace "$WORKSPACE" >"$WORKSPACE/onboard.json"

python3 - "$WORKSPACE/onboard.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["summary"]["workspace_count"] == 1, payload
result = payload["results"][0]
assert result["install_status"] == "installed", result
assert result["coverage_hook_status"] == "ok", result
assert result["hook_visibility"] in {"unknown", "probe_unavailable"}, result
assert result["onboarding_status"] == "configured_check_ui", result
PY

printf '%s\n' '{"run":{"eventName":"preToolUse","sessionId":"session-a","turnId":"turn-a","cwd":"'"$WORKSPACE"'"}}' \
  | python3 "$ROOT_DIR/script/codex_hook_event.py" --event-json - --spool-dir "$TASKLIGHT_SIGNAL_SPOOL_DIR" >/dev/null

python3 - "$TASKLIGHT_SIGNAL_SPOOL_DIR" "$TASKLIGHT_NORMALIZED_SIGNALS_PATH" "$WORKSPACE" <<'PY'
import json
import sys
from pathlib import Path

spool_dir = Path(sys.argv[1])
bus_path = Path(sys.argv[2])
workspace = sys.argv[3]

spool = []
for path in sorted(spool_dir.glob("*.jsonl")):
    spool.extend(json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip())
bus = [json.loads(line) for line in bus_path.read_text(encoding="utf-8").splitlines() if line.strip()]
assert spool, "expected at least one spooled hook signal"
assert spool[-1]["event_type"] == "item_started", spool[-1]
assert spool[-1]["turn_id"] == "turn-a", spool[-1]
assert spool[-1]["session_id"] == "session-a", spool[-1]
assert spool[-1]["cwd"] == workspace, spool[-1]
assert bus[-1]["event_type"] == "item_started", bus[-1]
assert bus[-1]["turn_id"] == "turn-a", bus[-1]
assert bus[-1]["session_id"] == "session-a", bus[-1]
assert bus[-1]["cwd"] == workspace, bus[-1]
PY

if python3 "$ROOT_DIR/script/onboard_workspace_for_monitoring.py" --json --workspace "$WORKSPACE/does-not-exist" >/dev/null 2>&1; then
  echo "expected missing workspace onboarding to fail" >&2
  exit 1
fi

echo "smoke_workspace_onboarding=ok"
