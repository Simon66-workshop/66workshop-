#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
STATE_DIR="$TMP_ROOT/state"
PLUGIN_DIR="$STATE_DIR/providers"
mkdir -p "$PLUGIN_DIR/manifests"

cat >"$TMP_ROOT/provider.sh" <<'SH'
#!/bin/sh
printf '%s\n' '{"health":"ok","quota_text":"Q42","remaining_percent":42,"is_low_quota":false,"source_label":"smoke provider","freshness_label":"fresh"}'
SH
chmod +x "$TMP_ROOT/provider.sh"
cat >"$PLUGIN_DIR/manifests/smoke.json" <<JSON
{"schema_version":"0.1","id":"smoke","display_name":"Smoke Provider","enabled":true,"executable":"$TMP_ROOT/provider.sh","timeout_seconds":5}
JSON
TASKLIGHT_STATE_DIR="$STATE_DIR" python3 "$ROOT_DIR/script/tasklight_provider_plugins.py" --once >/dev/null
python3 - "$PLUGIN_DIR/snapshots/smoke.json" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
assert payload["health"] == "disabled", payload
assert payload["freshness_label"] == "user opt-in required", payload
PY

cat >"$PLUGIN_DIR/provider_opt_in.json" <<'JSON'
{"schema_version":"0.1","explicit_user_opt_in":true,"provider_ids":["smoke"]}
JSON
TASKLIGHT_STATE_DIR="$STATE_DIR" python3 "$ROOT_DIR/script/tasklight_provider_plugins.py" --once >/dev/null
python3 - "$PLUGIN_DIR/snapshots/smoke.json" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
assert payload["id"] == "smoke", payload
assert payload["health"] == "ok", payload
assert payload["diagnostic_only"] is True, payload
assert payload["remaining_percent"] == 42, payload
PY

cat >"$STATE_DIR/state_projector_health.json" <<'JSON'
{"status":"ok","workspace":"/Users/example/private","message":"secret prompt text","auth_token":"never-include-this"}
JSON

TASKLIGHT_STATE_DIR="$STATE_DIR" python3 "$ROOT_DIR/script/create_diagnostic_bundle.py" --output "$TMP_ROOT/diagnostics.zip" >/dev/null
python3 - "$TMP_ROOT/diagnostics.zip" <<'PY'
import sys
import zipfile
from pathlib import Path

path = Path(sys.argv[1])
assert path.exists()
with zipfile.ZipFile(path) as archive:
    names = set(archive.namelist())
    assert "manifest.json" in names, names
    forbidden = [name for name in names if "normalized_signals" in name or "events.jsonl" in name or "auth" in name]
    assert not forbidden, forbidden
    combined = b"".join(archive.read(name) for name in names)
    assert b"never-include-this" not in combined
    assert b"secret prompt text" not in combined
    assert b"/Users/example/private" not in combined
PY

openssl genpkey -algorithm Ed25519 -out "$TMP_ROOT/update-private.pem" >/dev/null 2>&1
chmod 600 "$TMP_ROOT/update-private.pem"
openssl pkey -in "$TMP_ROOT/update-private.pem" -pubout -out "$TMP_ROOT/update-public.pem" >/dev/null 2>&1
cat >"$TMP_ROOT/update.json" <<'JSON'
{"schema_version":"0.1","version":"4.0.0","artifact":"66TaskLight.zip","sha256":"0123456789abcdef"}
JSON
python3 "$ROOT_DIR/script/sign_update_manifest.py" --manifest "$TMP_ROOT/update.json" --private-key "$TMP_ROOT/update-private.pem" --output "$TMP_ROOT/update.signed.json" >/dev/null
python3 "$ROOT_DIR/script/verify_update_manifest.py" --manifest "$TMP_ROOT/update.signed.json" --public-key "$TMP_ROOT/update-public.pem" >/dev/null
python3 - "$TMP_ROOT/update.signed.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["version"] = "4.0.1-tampered"
path.write_text(json.dumps(payload))
PY
if python3 "$ROOT_DIR/script/verify_update_manifest.py" --manifest "$TMP_ROOT/update.signed.json" --public-key "$TMP_ROOT/update-public.pem" >/dev/null 2>&1; then
  echo "tampered update manifest was accepted" >&2
  exit 1
fi

rg -q 'RegisterEventHotKey' "$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/TaskLightGlobalShortcutController.swift"
rg -q '66TaskLightWidgetExtension' "$ROOT_DIR/mac/66TaskLight/project.yml"
rg -q 'app-extension' "$ROOT_DIR/mac/66TaskLight/project.yml"
python3 "$ROOT_DIR/script/check_release_readiness.py" >"$TMP_ROOT/release.json"
python3 - "$TMP_ROOT/release.json" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text())
assert payload["widget_target_configured"] is True, payload
assert payload["signed_update_workflow"] is True, payload
assert payload["production_signing_status"] in {"ready", "blocked_missing_codesign_identity"}, payload
PY

echo "smoke_expansion_m40=ok"
