#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
OBS_STATE_PATH="${TASKLIGHT_OBSERVATIONS_STATE_PATH:-$STATE_DIR/observations_state.json}"
LABEL="${TASKLIGHT_OBSERVER_LABEL:-com.local.66tasklight.observer}"
MATCH="${TASKLIGHT_OBSERVER_MATCH:-observe-local --watch}"
MAX_AGE_SECONDS="${TASKLIGHT_OBSERVER_MAX_AGE_SECONDS:-15}"

observer_watch_status="not_running"
if pgrep -f "$MATCH" >/dev/null 2>&1; then
  observer_watch_status="running"
fi

observations_state_status="missing_empty_ok"
observations_state_updated_at="n/a"
observations_state_age_seconds="n/a"
observations_state_fresh="no"

if [ -s "$OBS_STATE_PATH" ]; then
  _observer_health_output="$(python3 - "$OBS_STATE_PATH" "$MAX_AGE_SECONDS" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

path = Path(sys.argv[1])
max_age = int(sys.argv[2])

try:
    payload = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    print("unreadable_error")
    print("n/a")
    print("n/a")
    print("no")
    raise SystemExit(0)

updated_at = payload.get("updated_at") or payload.get("generated_at")
print("readable")
print(updated_at or "n/a")
if updated_at:
    normalized = updated_at.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        print("n/a")
        print("no")
        raise SystemExit(0)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    age = max(0, int((datetime.now(timezone.utc) - parsed.astimezone(timezone.utc)).total_seconds()))
    print(str(age))
    print("yes" if age <= max_age else "no")
else:
    print("n/a")
    print("no")
PY
)"
  observations_state_status="$(printf '%s\n' "$_observer_health_output" | sed -n '1p')"
  observations_state_updated_at="$(printf '%s\n' "$_observer_health_output" | sed -n '2p')"
  observations_state_age_seconds="$(printf '%s\n' "$_observer_health_output" | sed -n '3p')"
  observations_state_fresh="$(printf '%s\n' "$_observer_health_output" | sed -n '4p')"
fi

echo "observer_label=$LABEL"
echo "observer_match=$MATCH"
echo "observer_watch_status=$observer_watch_status"
echo "state_dir=$STATE_DIR"
echo "observations_state_path=$OBS_STATE_PATH"
echo "observations_state_status=$observations_state_status"
echo "observations_state_updated_at=$observations_state_updated_at"
echo "observations_state_age_seconds=$observations_state_age_seconds"
echo "observations_state_fresh=$observations_state_fresh"
