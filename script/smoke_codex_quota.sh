#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-quota-XXXXXX")"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_UI_STATE_PATH="$STATE_DIR/ui_state.json"
export TASKLIGHT_QUOTA_STATE_PATH="$STATE_DIR/quota_state.json"
export TASKLIGHT_NORMALIZED_SIGNALS_PATH="$STATE_DIR/normalized_signals.jsonl"
export TASKLIGHT_SIGNAL_BUS_MAX_AGE_SECONDS=9999999999
export TASKLIGHT_APPSERVER_THREAD_OBSERVER_DISABLED=1

mkdir -p "$STATE_DIR/tasks" "$STATE_DIR/turn_bindings"

python3 "$ROOT_DIR/script/codex_quota_import.py" --text $'5小时 93% 11:44\n1周 42% 6月18日\n3次可用重置\n| status | issued date | expiry date | redeemed yes/no |\n|---|---:|---:|---|\n| available | 2026-06-18 | 2026-07-18 | no |\n| available | 2026-06-26 | 2026-07-26 | no |\n| available | 2026-07-01 | 2026-07-31 | no |' >/dev/null
python3 - "$TASKLIGHT_QUOTA_STATE_PATH" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding="utf-8"))
assert p["raw_windows"][0]["remaining_percent"] == 93, p
assert p["display_windows"][0]["remaining_percent"] == 93, p
assert p["display_windows"][-1]["remaining_percent"] == 42, p
assert p["manual_resets"]["available_count"] == 3, p
assert p["manual_resets"]["total_count"] == 3, p
assert p["manual_resets"]["next_expiry"] == "2026-07-18", p
assert len(p["manual_resets"]["credits"]) == 3, p
assert p["effective_remaining_percent"] == 42, p
assert p["quota_status"] == "watch", p
PY

python3 "$ROOT_DIR/script/state_projector.py" --once >/dev/null
python3 - "$TASKLIGHT_UI_STATE_PATH" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding="utf-8"))
q=p.get("quota")
assert q and q["fresh"] is True, p
assert q["short_percent"] == 93 and q["long_percent"] == 42, q
assert q["display_windows"][0]["remaining_percent"] == 93, q
assert q["raw_window_count"] == 2, q
assert q["manual_resets_available"] == 3, q
assert q["manual_resets_total_count"] == 3, q
assert q["manual_resets_next_expiry"] == "2026-07-18", q
assert len(q["manual_reset_credits"]) == 3, q
assert p["global_status"] == "idle", p
PY

python3 - "$TASKLIGHT_QUOTA_STATE_PATH" "$ROOT_DIR" <<'PY'
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[2]) / "script"))
from codex_quota_import import normalize_appserver_response

payload = normalize_appserver_response({
    "rateLimits": [
        {
            "limitId": "codex_bengalfox",
            "primary": {"usedPercent": 3, "windowDurationMins": 300, "resetsAt": 4102444800},
            "secondary": {"usedPercent": 57, "windowDurationMins": 10080, "resetsAt": 4102444800}
        },
        {
            "limitId": "codex",
            "primary": {"usedPercent": 2, "windowDurationMins": 300, "resetsAt": 4102444800},
            "secondary": {"usedPercent": 60, "windowDurationMins": 10080, "resetsAt": 4102444800}
        }
    ],
    "rateLimitResetCredits": {
        "credits": [
            {"status": "available", "issued_at": "2026-06-18", "expires_at": "2026-07-18", "redeemed": False},
            {"status": "available", "issued_at": "2026-06-26", "expires_at": "2026-07-26", "redeemed": False},
            {"status": "available", "issued_at": "2026-07-01", "expires_at": "2026-07-31", "redeemed": False}
        ]
    }
})
assert len(payload["raw_windows"]) == 4, payload
assert payload["display_windows"][0]["bucket_id"] == "codex", payload
assert payload["display_windows"][0]["remaining_percent"] == 98, payload
assert payload["display_windows"][-1]["bucket_id"] == "codex", payload
assert payload["display_windows"][-1]["remaining_percent"] == 40, payload
assert payload["effective_remaining_percent"] == 40, payload
assert payload["manual_resets"]["available_count"] == 3, payload
assert payload["manual_resets"]["next_expiry"] == "2026-07-18", payload
json.dump(payload, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
python3 "$ROOT_DIR/script/state_projector.py" --once >/dev/null
python3 - "$TASKLIGHT_UI_STATE_PATH" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding="utf-8"))
q=p.get("quota")
assert q["short_percent"] == 98, q
assert q["long_percent"] == 40, q
assert q["bucket_id"] == "codex", q
assert q["raw_window_count"] == 4, q
assert q["display_windows"][0]["bucket_id"] == "codex", q
assert q["manual_resets_available"] == 3, q
assert q["manual_resets_next_expiry"] == "2026-07-18", q
PY

python3 - "$ROOT_DIR" <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, str(Path(sys.argv[1]) / "script"))
from codex_quota_import import normalize_appserver_response

payload = normalize_appserver_response({
    "rateLimits": [{
        "limitId": "codex",
        "primary": {"usedPercent": 4.5, "windowDurationMins": 300, "resetsAt": 4102444800},
        "secondary": {"usedPercent": 8.5, "windowDurationMins": 10080, "resetsAt": 4102444800},
    }]
})
assert payload["display_windows"][0]["remaining_percent"] == 96, payload
assert payload["display_windows"][0]["used_percent"] == 4, payload
assert payload["display_windows"][1]["remaining_percent"] == 92, payload
assert payload["display_windows"][1]["used_percent"] == 8, payload
PY

python3 "$ROOT_DIR/script/codex_quota_import.py" --text $'5小时 97% 11:44\n1周 97% 6月18日' >/dev/null
python3 "$ROOT_DIR/script/state_projector.py" --once >/dev/null
python3 - "$TASKLIGHT_UI_STATE_PATH" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding="utf-8"))
q=p.get("quota")
assert q and q["fresh"] is True, p
assert q["short_percent"] == 97 and q["long_percent"] == 97, q
assert q["effective_remaining_percent"] == 97, q
assert len(q["display_windows"]) == 2, q
assert p["global_status"] == "idle", p
PY

python3 "$ROOT_DIR/script/codex_quota_import.py" --text "5小时 3% 11:44" >/dev/null
python3 - "$TASKLIGHT_QUOTA_STATE_PATH" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding="utf-8"))
assert p["quota_status"] == "critical", p
PY

if python3 "$ROOT_DIR/script/codex_quota_import.py" --text "5小时 130% 11:44" >/dev/null 2>&1; then
  echo "expected invalid percent to fail" >&2
  exit 1
fi

rm -f "$TASKLIGHT_QUOTA_STATE_PATH"
python3 "$ROOT_DIR/script/state_projector.py" --once >/dev/null
python3 - "$TASKLIGHT_UI_STATE_PATH" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding="utf-8"))
assert p.get("quota") is None, p
assert p["diagnostics"].get("quota_status") == "missing", p
PY

cat >"$STATE_DIR/tasks/done-task.json" <<'JSON'
{
  "schema_version": 3,
  "task_id": "done-task",
  "short_task_id": "done",
  "title": "Done task",
  "slug": "done-task",
  "status": "done_verified",
  "raw_status": "done_verified",
  "effective_status": "done_verified",
  "created_at": "2099-01-01T00:00:00Z",
  "updated_at": "2099-01-01T00:00:00Z",
  "verified_at": "2099-01-01T00:00:00Z"
}
JSON
python3 "$ROOT_DIR/script/codex_quota_import.py" --text $'5小时 93% 11:44\n1周 42% 6月18日\n1次可用重置' >/dev/null
python3 "$ROOT_DIR/script/state_projector.py" --once >/dev/null
python3 - "$TASKLIGHT_UI_STATE_PATH" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding="utf-8"))
assert p["global_status"] == "done_verified", p
assert p["lamp_status"] == "done_verified", p
assert p["global_display_title"] == "DONE", p
assert p["quota"]["status"] == "watch", p
PY

"$ROOT_DIR/script/check_codex_quota.sh" >/dev/null
echo "smoke_codex_quota: ok"
