#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT_DIR/script/check_codex_hooks_trust.py"
HANDLER="$ROOT_DIR/script/codex_hook_event.py"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-hooks-config-XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
STATE_DIR="$TMP_DIR/state"
mkdir -p "$STATE_DIR"

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_NORMALIZED_SIGNALS_PATH="$STATE_DIR/normalized_signals.jsonl"

# A Codex desktop update may move the bundled app-server binary. The probe must
# honor an explicitly configured local binary instead of assuming Codex.app.
python3 - "$CHECKER" "$TMP_DIR" <<'PY'
import importlib.util
import os
import stat
import sys
from pathlib import Path

checker = Path(sys.argv[1])
tmp = Path(sys.argv[2])
override = tmp / "codex-local"
override.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
override.chmod(override.stat().st_mode | stat.S_IXUSR)
spec = importlib.util.spec_from_file_location("hooks_check", checker)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
previous = os.environ.get("TASKLIGHT_CODEX_BIN")
os.environ["TASKLIGHT_CODEX_BIN"] = str(override)
try:
    assert module.resolve_codex_binary() == override
finally:
    if previous is None:
        os.environ.pop("TASKLIGHT_CODEX_BIN", None)
    else:
        os.environ["TASKLIGHT_CODEX_BIN"] = previous
PY

status_for() {
  local project_root="$1"
  python3 "$CHECKER" --project-root "$project_root" --expected-root "$project_root" --skip-appserver --json \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])'
}

case_root() {
  local name="$1"
  local path="$TMP_DIR/$name"
  mkdir -p "$path/.codex" "$path/script"
  printf '%s\n' "$path"
}

missing_hooks="$(case_root missing-hooks)"
[[ "$(status_for "$missing_hooks")" == "misconfigured" ]]

invalid_hooks="$(case_root invalid-hooks)"
printf '{bad json\n' >"$invalid_hooks/.codex/hooks.json"
[[ "$(status_for "$invalid_hooks")" == "misconfigured" ]]

missing_handler="$(case_root missing-handler)"
cat >"$missing_handler/.codex/hooks.json" <<'JSON'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"script/codex_hook_event.py --event-json -"}]}]}}
JSON
[[ "$(status_for "$missing_handler")" == "misconfigured" ]]

not_executable="$(case_root not-executable)"
cat >"$not_executable/.codex/hooks.json" <<'JSON'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"script/codex_hook_event.py --event-json -"}]}]}}
JSON
cp "$HANDLER" "$not_executable/script/codex_hook_event.py"
chmod 0644 "$not_executable/script/codex_hook_event.py"
[[ "$(status_for "$not_executable")" == "misconfigured" ]]

valid_hooks="$(case_root valid-hooks)"
cat >"$valid_hooks/.codex/hooks.json" <<'JSON'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"script/codex_hook_event.py --event-json -"}]}]}}
JSON
cp "$HANDLER" "$valid_hooks/script/codex_hook_event.py"
chmod 0755 "$valid_hooks/script/codex_hook_event.py"
[[ "$(status_for "$valid_hooks")" == "trusted_possible" ]]

health_json="$(python3 "$HANDLER" --health)"
python3 - "$health_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["ok"] is True, payload
assert payload["writes_task_state"] is False, payload
PY

lower_camel_signal="$(printf '%s\n' '{"eventName":"userPromptSubmit","threadId":"thread-a","turnId":"turn-a"}' | python3 "$HANDLER" --event-json -)"
python3 - "$lower_camel_signal" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["event_type"] == "turn_started", payload
assert payload["thread_id"] == "thread-a", payload
assert payload["turn_id"] == "turn-a", payload
assert payload["confidence"] == 0.85, payload
PY

nested_signal="$(printf '%s\n' '{"run":{"eventName":"postToolUse","threadId":"thread-a","turnId":"turn-a","cwd":"/tmp/tasklight-workspace"},"exitCode":1}' | python3 "$HANDLER" --event-json -)"
python3 - "$nested_signal" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["event_type"] == "tool_failed", payload
assert payload["thread_id"] == "thread-a", payload
assert payload["turn_id"] == "turn-a", payload
assert payload["cwd"] == "/tmp/tasklight-workspace", payload
assert payload["reason"] == "codex_exit_failed", payload
PY

title_case_signal="$(printf '%s\n' '{"event":"PreToolUse","turn_id":"turn-a"}' | python3 "$HANDLER" --event-json -)"
python3 - "$title_case_signal" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["event_type"] == "item_started", payload
assert payload["raw_event_ref"] == "preToolUse", payload
PY

echo "smoke_hooks_config: ok"
