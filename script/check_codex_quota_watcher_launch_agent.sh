#!/usr/bin/env bash
set -euo pipefail

LABEL="${TASKLIGHT_QUOTA_WATCHER_LABEL:-com.66tasklight.quota-watcher}"
PLIST_PATH="${TASKLIGHT_QUOTA_WATCHER_PLIST:-$HOME/Library/LaunchAgents/${LABEL}.plist}"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
HEALTH_PATH="${TASKLIGHT_QUOTA_PROBE_HEALTH_PATH:-$STATE_DIR/quota_probe_health.json}"

launch_status="not_running"
if launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
  launch_status="running"
fi

process_pid="$(pgrep -f "codex_quota_appserver_watcher.py.*--watch" | head -1 || true)"
plist_exists="no"
[[ -f "$PLIST_PATH" ]] && plist_exists="yes"

python3 - "$HEALTH_PATH" "$plist_exists" "$launch_status" "$process_pid" <<'PY'
import json
import sys
import time
from datetime import datetime
from pathlib import Path

health_path = Path(sys.argv[1]).expanduser()
plist_exists = sys.argv[2]
launch_status = sys.argv[3]
process_pid = sys.argv[4] or "none"

def parse_ts(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None

payload = {}
try:
    payload = json.loads(health_path.read_text(encoding="utf-8"))
except Exception:
    payload = {}

last_probe_age = None
parsed = parse_ts(payload.get("last_probe_at") or payload.get("updated_at"))
if parsed is not None:
    last_probe_age = round(max(0.0, time.time() - parsed), 2)

status = "ok"
if plist_exists != "yes" or launch_status != "running":
    status = "not_running"
elif not payload:
    status = "stale"
elif payload.get("status") == "error":
    status = "error"

print(f"plist_exists={plist_exists}")
print(f"launchctl_status={launch_status}")
print(f"process_pid={process_pid}")
print(f"quota_probe_health_path={health_path}")
print(f"quota_probe_status={payload.get('status', 'missing')}")
print(f"quota_probe_mode={payload.get('mode', 'unknown')}")
print(f"latest_probe_age_sec={last_probe_age if last_probe_age is not None else 'none'}")
print(f"last_error={payload.get('last_error') or 'none'}")
print(f"STATUS={status}")
PY
