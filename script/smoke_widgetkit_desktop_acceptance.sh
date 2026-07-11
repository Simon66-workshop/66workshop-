#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT_DIR/script/check_widgetkit_desktop_acceptance.py"

[[ -f "$CHECK" ]] || { echo "widget desktop acceptance check is missing" >&2; exit 1; }
rg -q "blocked_missing_codesign_identity" "$CHECK"
rg -q "ready_for_human_desktop_acceptance" "$CHECK"
rg -q "widget_is_sanitized" "$CHECK"

payload="$(python3 "$CHECK")"
python3 - "$payload" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] in {"ready_for_human_desktop_acceptance", "blocked_missing_codesign_identity"}, payload
assert payload["production_ready"] is False, payload
assert payload["checks"]["app_group_declared"] is True, payload
assert payload["checks"]["widget_is_sanitized"] is True, payload
PY

echo "smoke_widgetkit_desktop_acceptance=ok"
echo "STATUS=ok"
