#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FUSION="$ROOT_DIR/script/codex_signal_fusion.py"
APPSERVER="$ROOT_DIR/script/codex_appserver_bridge.py"
HOOK="$ROOT_DIR/script/codex_hook_event.py"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-fusion-XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
export TASKLIGHT_STATE_DIR="$TMP_DIR/state"
export TASKLIGHT_NORMALIZED_SIGNALS_PATH="$TASKLIGHT_STATE_DIR/normalized_signals.jsonl"
export TASKLIGHT_SIGNAL_SPOOL_DIR="$TASKLIGHT_STATE_DIR/signals"
mkdir -p "$TASKLIGHT_STATE_DIR" "$TASKLIGHT_SIGNAL_SPOOL_DIR"

assert_field() {
  local json="$1"
  local expr="$2"
  python3 - "$json" "$expr" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
expr = sys.argv[2]
key, expected = expr.split("=", 1)
actual = payload
for part in key.split("."):
    actual = actual.get(part)
assert str(actual) == expected, payload
PY
}

cat >"$TMP_DIR/turn_started.json" <<'JSON'
{"method":"turn/started","params":{"thread_id":"thread-a","turn_id":"turn-1","event_time":100}}
JSON
turn_started="$("$APPSERVER" --fixture "$TMP_DIR/turn_started.json" | "$FUSION" --input -)"
assert_field "$turn_started" "inferred_status=running"
assert_field "$turn_started" "decision=refresh_managed_heartbeat"

cat >"$TMP_DIR/approval.json" <<'JSON'
{"method":"item/commandExecution/requestApproval","params":{"thread_id":"thread-a","turn_id":"turn-1","item_id":"item-1","event_time":101}}
JSON
approval="$("$APPSERVER" --fixture "$TMP_DIR/approval.json" | "$FUSION" --input -)"
assert_field "$approval" "inferred_status=blocked"
assert_field "$approval" "blocker_reason=needs_human_review"

cat >"$TMP_DIR/completed.json" <<'JSON'
{"method":"turn/completed","params":{"thread_id":"thread-a","turn_id":"turn-1","event_time":102}}
JSON
completed="$("$APPSERVER" --fixture "$TMP_DIR/completed.json" | "$FUSION" --input -)"
assert_field "$completed" "inferred_status=done_unverified"
assert_field "$completed" "decision=mark_done_unverified"

cat >"$TMP_DIR/appserver_quiet.json" <<'JSON'
{"method":"thread/status/changed","params":{"thread_id":"thread-a","status":{"type":"idle"},"event_time":103}}
JSON
appserver_quiet="$("$APPSERVER" --fixture "$TMP_DIR/appserver_quiet.json" | "$FUSION" --input - --quiet-count 3)"
assert_field "$appserver_quiet" "inferred_status=quiet"
assert_field "$appserver_quiet" "decision=release_binding"

stop_signal="$(printf '%s\n' '{"hook":"Stop","thread_id":"thread-a","turn_id":"turn-1"}' | "$HOOK" --event-json - | "$FUSION" --input -)"
assert_field "$stop_signal" "inferred_status=done_unverified"
assert_field "$stop_signal" "decision=mark_done_unverified"

turn_only_signal="$(printf '%s\n' '{"eventName":"preToolUse","turnId":"turn-only-1"}' | env -u CODEX_THREAD_ID "$HOOK" --event-json - | "$FUSION" --input -)"
assert_field "$turn_only_signal" "inferred_status=running"
assert_field "$turn_only_signal" "task_identity=turn:turn-only-1"

verify_wins="$(cat <<'JSON' | "$FUSION" --input -
[
  {"source":"codex_private_probe","event_type":"private_active","thread_id":"thread-a","confidence":0.9,"thread_scoped":true},
  {"source":"explicit","event_type":"verified","thread_id":"thread-a","task_id":"task-a","confidence":1}
]
JSON
)"
assert_field "$verify_wins" "inferred_status=done_verified"

echo "smoke_signal_fusion: ok"
