#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-quota-watch-XXXXXX")"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_QUOTA_STATE_PATH="$STATE_DIR/quota_state.json"
export TASKLIGHT_QUOTA_PROBE_HEALTH_PATH="$STATE_DIR/quota_probe_health.json"
export TASKLIGHT_UI_STATE_PATH="$STATE_DIR/ui_state.json"

cat >"$STATE_DIR/rate-limit-updated.json" <<'JSON'
{
  "method": "account/rateLimits/updated",
  "params": {
    "result": {
      "rateLimits": [
        {
          "limitId": "codex_bengalfox",
          "limitName": "Codex Bengalfox",
          "primary": {"usedPercent": 9, "windowDurationMins": 300, "resetsAt": 4102444800},
          "secondary": {"usedPercent": 62, "windowDurationMins": 10080, "resetsAt": 4102444800}
        },
        {
          "limitId": "codex",
          "limitName": "Codex",
          "primary": {"usedPercent": 2, "windowDurationMins": 300, "resetsAt": 4102444800},
          "secondary": {"usedPercent": 60, "windowDurationMins": 10080, "resetsAt": 4102444800}
        }
	      ],
	      "rateLimitResetCredits": {
	        "credits": [
	          {"status": "available", "issued_at": "2026-06-18", "expires_at": "2026-07-18", "redeemed": false},
	          {"status": "available", "issued_at": "2026-06-26", "expires_at": "2026-07-26", "redeemed": false},
	          {"status": "available", "issued_at": "2026-07-01", "expires_at": "2026-07-31", "redeemed": false}
	        ]
	      }
	    }
  }
}
JSON

python3 "$ROOT_DIR/script/codex_quota_appserver_watcher.py" --once --fixture "$STATE_DIR/rate-limit-updated.json" >/dev/null

python3 - "$TASKLIGHT_QUOTA_STATE_PATH" "$TASKLIGHT_QUOTA_PROBE_HEALTH_PATH" <<'PY'
import json, sys
quota=json.load(open(sys.argv[1], encoding="utf-8"))
health=json.load(open(sys.argv[2], encoding="utf-8"))
assert health["status"] == "ok", health
assert health["mode"] == "event_fixture", health
assert health["last_event_at"], health
assert quota["display_windows"][0]["bucket_id"] == "codex", quota
assert quota["display_windows"][0]["remaining_percent"] == 98, quota
assert quota["display_windows"][-1]["remaining_percent"] == 40, quota
assert len(quota["raw_windows"]) == 4, quota
assert quota["manual_resets"]["available_count"] == 3, quota
assert quota["manual_resets"]["next_expiry"] == "2026-07-18", quota
PY

cat >"$STATE_DIR/rate-limit-updated-unsupported.json" <<'JSON'
{"method":"account/rateLimits/updated","params":{"result":{"rateLimitsVNext":[]}}}
JSON
python3 "$ROOT_DIR/script/codex_quota_appserver_watcher.py" --once --fixture "$STATE_DIR/rate-limit-updated-unsupported.json" >/dev/null

python3 - "$TASKLIGHT_QUOTA_STATE_PATH" "$TASKLIGHT_QUOTA_PROBE_HEALTH_PATH" <<'PY'
import json, sys
quota=json.load(open(sys.argv[1], encoding="utf-8"))
health=json.load(open(sys.argv[2], encoding="utf-8"))
assert quota["source"] == "codex_appserver_cached", quota
assert quota["fresh"] is False, quota
assert "appserver_schema_changed" in quota["warnings"], quota
assert health["status"] == "degraded", health
assert health["fallback_active"] is True, health
assert health["last_success_at"], health
PY

python3 "$ROOT_DIR/script/state_projector.py" --once >/dev/null
python3 - "$TASKLIGHT_UI_STATE_PATH" <<'PY'
import json, sys
state=json.load(open(sys.argv[1], encoding="utf-8"))
quota=state.get("quota")
assert quota and quota["fresh"] is False, state
assert quota["source"] == "codex_appserver_cached", quota
assert state["global_status"] == "idle", state
PY

echo "smoke_codex_quota_watcher: ok"
