#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPSERVER="$ROOT_DIR/script/codex_appserver_bridge.py"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-appserver-XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

probe_json="$("$APPSERVER" --probe)"
python3 - "$probe_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["source"] == "codex_appserver", payload
assert "supports_stdio" in payload, payload
assert "client_request_methods" in payload, payload
assert "server_notification_methods" in payload, payload
PY

listen_json="$("$APPSERVER" --listen --timeout 0.5 --thread-id "tasklight-smoke-no-thread")"
python3 - "$listen_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert isinstance(payload, list) and payload, payload
for signal in payload:
    assert signal.get("source") == "codex_appserver", signal
    encoded = json.dumps(signal).lower()
    forbidden = ["preview", "prompt", "response_text", "raw log", "auth.json"]
    assert not any(item in encoded for item in forbidden), signal
PY

cat >"$TMP_DIR/idle.json" <<'JSON'
{"method":"thread/status/changed","params":{"thread_id":"thread-a","status":{"type":"idle"},"event_time":100}}
JSON
idle_json="$("$APPSERVER" --fixture "$TMP_DIR/idle.json")"
python3 - "$idle_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload[0]["event_type"] == "appserver_quiet", payload
PY

echo "smoke_appserver_bridge: ok"
