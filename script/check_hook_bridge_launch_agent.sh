#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="${TASKLIGHT_HOOK_BRIDGE_LABEL:-com.66tasklight.hook-bridge}"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
SIGNAL_DIR="${TASKLIGHT_SIGNAL_SPOOL_DIR:-$STATE_DIR/signals}"
TURN_BINDINGS_DIR="${TASKLIGHT_TURN_BINDINGS_DIR:-$STATE_DIR/turn_bindings}"
OFFSETS_PATH="${TASKLIGHT_HOOK_BRIDGE_OFFSETS_PATH:-$STATE_DIR/hook_bridge_offsets.json}"
HEALTH_PATH="${TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH:-$STATE_DIR/hook_bridge_health.json}"
LOG_DIR="${TASKLIGHT_HOOK_BRIDGE_LOG_DIR:-$STATE_DIR/logs}"
ERR_LOG="$LOG_DIR/hook_bridge.err.log"
PLIST_DIR="${TASKLIGHT_HOOK_BRIDGE_PLIST_DIR:-$HOME/Library/LaunchAgents}"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"
MAX_BRIDGE_AGE_SECONDS="${TASKLIGHT_HOOK_BRIDGE_MAX_AGE_SECONDS:-15}"
MAX_PROCESSING_AGE_SECONDS="${TASKLIGHT_HOOK_BRIDGE_PROCESSING_MAX_AGE_SECONDS:-120}"

plist_exists="no"
if [ -f "$PLIST_PATH" ]; then
  plist_exists="yes"
fi

launchctl_status="not_running"
launchctl_pid=""
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  launchctl_status="running"
  launchctl_pid="$(launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | awk '/pid = /{print $3; exit}' || true)"
elif [ "$plist_exists" = "yes" ]; then
  launchctl_status="not_running"
fi

process_pid="$launchctl_pid"
if [ -z "$process_pid" ]; then
  process_pid="$(pgrep -f "$ROOT_DIR/script/hook_signal_bridge.py --watch" | head -1 || true)"
fi
if [ -z "$process_pid" ]; then
  process_pid="$(pgrep -f "hook_signal_bridge.py --watch" | head -1 || true)"
fi
if [ -z "$process_pid" ]; then
  process_pid="none"
fi

_health_output="$(python3 - "$SIGNAL_DIR" "$TURN_BINDINGS_DIR" "$OFFSETS_PATH" "$HEALTH_PATH" "$MAX_BRIDGE_AGE_SECONDS" "$MAX_PROCESSING_AGE_SECONDS" <<'PY'
from __future__ import annotations

import json
import sys
import time
from datetime import datetime
from collections import deque
from pathlib import Path

signal_dir = Path(sys.argv[1]).expanduser()
bindings_dir = Path(sys.argv[2]).expanduser()
offsets_path = Path(sys.argv[3]).expanduser()
health_path = Path(sys.argv[4]).expanduser()
max_age = float(sys.argv[5])


def parse_ts(value):
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value))
    except ValueError:
        pass
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


latest_signal_ts = None
if signal_dir.exists():
    for path in sorted(signal_dir.glob("*.jsonl")):
        try:
            with path.open("r", encoding="utf-8") as handle:
                lines = list(deque(handle, maxlen=50))
        except OSError:
            continue
        for line in lines:
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
            ts = parse_ts(payload.get("event_time"))
            if ts is not None:
                latest_signal_ts = max(latest_signal_ts or ts, ts)

active = 0
if bindings_dir.exists():
    for path in bindings_dir.glob("*.json"):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        if payload.get("status") == "active":
            active += 1

offsets_status = "missing"
offset_last_run_at = None
offset_last_seen_at = None
if offsets_path.exists():
    try:
        offsets = json.loads(offsets_path.read_text(encoding="utf-8"))
        offsets_status = "readable"
        offset_last_run_at = offsets.get("last_run_at")
        offset_last_seen_at = offsets.get("last_seen_at")
    except (json.JSONDecodeError, OSError):
        offsets_status = "unreadable"

health_status = "missing"
health = {}
if health_path.exists():
    try:
        health = json.loads(health_path.read_text(encoding="utf-8"))
        health_status = "readable"
    except (json.JSONDecodeError, OSError):
        health_status = "unreadable"

last_run_at = health.get("last_run_at") or offset_last_run_at
last_seen_at = health.get("last_seen_at") or offset_last_seen_at
last_run_ts = parse_ts(last_run_at)
now = time.time()
signal_age = "none" if latest_signal_ts is None else str(max(0, int(now - latest_signal_ts)))
bridge_age = "none" if last_run_ts is None else str(max(0, int(now - last_run_ts)))
bridge_fresh = last_run_ts is not None and now - last_run_ts <= max_age
processing_fresh = (
    health.get("status") == "processing"
    and last_run_ts is not None
    and now - last_run_ts <= float(sys.argv[6])
)

print(f"signal_dir={signal_dir}")
print(f"latest_signal_age_sec={signal_age}")
print(f"active_turn_bindings={health.get('active_turn_bindings', active)}")
print(f"offsets_status={offsets_status}")
print(f"hook_bridge_health_path={health_path}")
print(f"hook_bridge_health_status={health_status}")
print(f"hook_bridge_health_state={health.get('status', 'none') if health_status == 'readable' else 'none'}")
print(f"latest_bridge_process_time={last_run_at or 'none'}")
print(f"latest_bridge_seen_time={last_seen_at or 'none'}")
print(f"latest_bridge_age_sec={bridge_age}")
print(f"bridge_fresh={'yes' if bridge_fresh else 'no'}")
print(f"processing_fresh={'yes' if processing_fresh else 'no'}")
PY
)"

latest_signal_age_sec="$(printf '%s\n' "$_health_output" | awk -F= '/^latest_signal_age_sec=/{print $2}' | tail -1)"
active_turn_bindings="$(printf '%s\n' "$_health_output" | awk -F= '/^active_turn_bindings=/{print $2}' | tail -1)"
offsets_status="$(printf '%s\n' "$_health_output" | awk -F= '/^offsets_status=/{print $2}' | tail -1)"
health_status="$(printf '%s\n' "$_health_output" | awk -F= '/^hook_bridge_health_status=/{print $2}' | tail -1)"
health_state="$(printf '%s\n' "$_health_output" | awk -F= '/^hook_bridge_health_state=/{print $2}' | tail -1)"
latest_bridge_process_time="$(printf '%s\n' "$_health_output" | awk -F= '/^latest_bridge_process_time=/{print $2}' | tail -1)"
bridge_fresh="$(printf '%s\n' "$_health_output" | awk -F= '/^bridge_fresh=/{print $2}' | tail -1)"
processing_fresh="$(printf '%s\n' "$_health_output" | awk -F= '/^processing_fresh=/{print $2}' | tail -1)"

status="ok"
if [ "$plist_exists" = "no" ] || [ "$launchctl_status" != "running" ] || [ "$process_pid" = "none" ]; then
  status="not_running"
elif [ "$offsets_status" = "unreadable" ] || [ "$health_status" = "unreadable" ]; then
  status="error"
elif [ "$health_state" = "error" ]; then
  status="error"
elif [ "$bridge_fresh" != "yes" ] && [ "$processing_fresh" != "yes" ]; then
  status="stale"
fi

log_tail="none"
if [ -s "$ERR_LOG" ]; then
  log_tail="$(tail -5 "$ERR_LOG" | tr '\n' '|' | sed 's/|$//')"
fi

echo "plist_exists=$plist_exists"
echo "launchctl_status=$launchctl_status"
echo "process_pid=$process_pid"
printf '%s\n' "$_health_output" | sed -n '/^signal_dir=/p'
echo "latest_signal_age_sec=${latest_signal_age_sec:-none}"
echo "active_turn_bindings=${active_turn_bindings:-0}"
printf '%s\n' "$_health_output" | sed -n '/^hook_bridge_health_path=/p'
echo "hook_bridge_health_status=${health_status:-missing}"
echo "hook_bridge_health_state=${health_state:-none}"
echo "latest_bridge_process_time=${latest_bridge_process_time:-none}"
echo "log_tail=$log_tail"
echo "STATUS=$status"
