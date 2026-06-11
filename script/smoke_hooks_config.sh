#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT_DIR/script/check_codex_hooks_trust.py"
HANDLER="$ROOT_DIR/script/codex_hook_event.py"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-hooks-config-XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

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

nested_signal="$(printf '%s\n' '{"run":{"eventName":"postToolUse"},"threadId":"thread-a","turnId":"turn-a","exitCode":1}' | python3 "$HANDLER" --event-json -)"
python3 - "$nested_signal" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["event_type"] == "tool_failed", payload
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
