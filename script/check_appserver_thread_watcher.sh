#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="${TASKLIGHT_APPSERVER_THREAD_WATCHER_LABEL:-com.66tasklight.appserver-thread-watch}"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
LOG_DIR="${TASKLIGHT_APPSERVER_THREAD_WATCHER_LOG_DIR:-$STATE_DIR/logs}"
PLIST_DIR="${TASKLIGHT_APPSERVER_THREAD_WATCHER_PLIST_DIR:-$HOME/Library/LaunchAgents}"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"
HEALTH_PATH="${TASKLIGHT_APPSERVER_THREAD_WATCHER_HEALTH_PATH:-$STATE_DIR/appserver_thread_watcher_health.json}"
MAX_AGE="${TASKLIGHT_APPSERVER_THREAD_WATCHER_MAX_AGE_SECONDS:-12}"
ERR_LOG="$LOG_DIR/appserver_thread_watcher.err.log"

plist_exists="no"
[ -f "$PLIST_PATH" ] && plist_exists="yes"

launchctl_status="not_running"
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  launchctl_status="running"
fi

process_pid="$(pgrep -f "$ROOT_DIR/script/appserver_thread_watcher.py --watch" | head -1 || true)"
[ -n "$process_pid" ] || process_pid="$(pgrep -f "appserver_thread_watcher.py --watch" | head -1 || true)"
[ -n "$process_pid" ] || process_pid="$(launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | awk '/^[[:space:]]pid = /{print $3; exit}' || true)"
[ -n "$process_pid" ] || process_pid="none"

_health_output="$(python3 - "$HEALTH_PATH" "$MAX_AGE" <<'PY'
import json
import sys
import time
from datetime import datetime
from pathlib import Path

health_path = Path(sys.argv[1]).expanduser()
max_age = float(sys.argv[2])

def parse_ts(value):
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        pass
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None

try:
    payload = json.loads(health_path.read_text(encoding="utf-8"))
    status = "readable"
except FileNotFoundError:
    payload = {}
    status = "missing"
except Exception:
    payload = {}
    status = "unreadable"

last_run = payload.get("last_run_at")
last_run_ts = parse_ts(last_run)
age = None if last_run_ts is None else max(0, int(time.time() - last_run_ts))
fresh = age is not None and age <= max_age

print(f"health_path={health_path}")
print(f"health_status={status}")
print(f"health_state={payload.get('status', 'none') if status == 'readable' else 'none'}")
print(f"latest_poll_age_sec={'none' if age is None else age}")
print(f"emitted_count={payload.get('emitted_count', 'none')}")
print(f"live_threads={payload.get('live_threads', 'none')}")
print(f"watcher_fresh={'yes' if fresh else 'no'}")
PY
)"

health_status="$(printf '%s\n' "$_health_output" | awk -F= '/^health_status=/{print $2}' | tail -1)"
health_state="$(printf '%s\n' "$_health_output" | awk -F= '/^health_state=/{print $2}' | tail -1)"
watcher_fresh="$(printf '%s\n' "$_health_output" | awk -F= '/^watcher_fresh=/{print $2}' | tail -1)"

status="ok"
if [ "$plist_exists" = "no" ] || [ "$launchctl_status" != "running" ] || [ "$process_pid" = "none" ]; then
  status="not_running"
elif [ "$health_status" = "unreadable" ] || [ "$health_state" = "error" ]; then
  status="error"
elif [ "$watcher_fresh" != "yes" ]; then
  status="stale"
fi

log_tail="none"
if [ -s "$ERR_LOG" ]; then
  log_tail="$(tail -5 "$ERR_LOG" | tr '\n' '|' | sed 's/|$//')"
fi

echo "plist_exists=$plist_exists"
echo "launchctl_status=$launchctl_status"
echo "process_pid=$process_pid"
printf '%s\n' "$_health_output"
echo "log_tail=$log_tail"
echo "STATUS=$status"
