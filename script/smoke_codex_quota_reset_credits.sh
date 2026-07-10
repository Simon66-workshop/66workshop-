#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-reset-credits-XXXXXX")"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_QUOTA_STATE_PATH="$STATE_DIR/quota_state.json"
export TASKLIGHT_UI_STATE_PATH="$STATE_DIR/ui_state.json"
export TASKLIGHT_SIGNAL_BUS_MAX_AGE_SECONDS=9999999999
export TASKLIGHT_APPSERVER_THREAD_OBSERVER_DISABLED=1

cat >"$STATE_DIR/reset-credits.json" <<'JSON'
{
  "credits": [
    {"status": "available", "issued_at": "2026-06-18T00:28:29Z", "expires_at": "2026-07-18T00:28:29Z", "redeemed": false},
    {"status": "available", "issued_at": "2026-06-26T23:12:43Z", "expires_at": "2026-07-26T23:12:43Z", "redeemed": false},
    {"status": "available", "issued_at": "2026-07-01T19:46:38Z", "expires_at": "2026-07-31T19:46:38Z", "redeemed": false}
  ]
}
JSON

python3 "$ROOT_DIR/script/codex_quota_import.py" --text $'5小时 88% 11:44\n1周 64% 6月18日' >/dev/null
python3 "$ROOT_DIR/script/codex_quota_reset_credits_probe.py" --fixture "$STATE_DIR/reset-credits.json" >/dev/null

python3 - "$TASKLIGHT_QUOTA_STATE_PATH" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding="utf-8"))
r=p["manual_resets"]
assert r["total_count"] == 3, p
assert r["available_count"] == 3, p
assert r["used_count"] == 0, p
assert r["expired_count"] == 0, p
assert "T" in r["next_expiry"], p
assert len(r["credits"]) == 3, p
assert r["credits"][0]["expires_at"].endswith("+08:00"), p
assert "access_token" not in json.dumps(p), p
PY

python3 "$ROOT_DIR/script/state_projector.py" --once >/dev/null
python3 - "$TASKLIGHT_UI_STATE_PATH" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding="utf-8"))
q=p.get("quota")
assert q["manual_resets_available"] == 3, q
assert q["manual_resets_total_count"] == 3, q
assert "T" in q["manual_resets_next_expiry"], q
assert len(q["manual_reset_credits"]) == 3, q
assert q["manual_reset_credits"][0]["expires_at"].endswith("+08:00"), q
assert p["global_status"] == "idle", p
PY

if rg -n "auth\\.json|urllib|Authorization|https?://|access_token|account_id" "$ROOT_DIR/script/codex_quota_reset_credits_probe.py"; then
  echo "reset credits importer must not read credentials or call external APIs" >&2
  exit 1
fi

echo "smoke_codex_quota_reset_credits=ok"
