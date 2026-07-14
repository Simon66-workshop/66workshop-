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

process_alive="no"
if [ "$process_pid" != "none" ]; then
  process_alive="yes"
fi

_health_output="$(python3 "$ROOT_DIR/script/hook_bridge_health.py" \
  --signal-dir "$SIGNAL_DIR" \
  --offsets-path "$OFFSETS_PATH" \
  --health-path "$HEALTH_PATH" \
  --process-alive "$process_alive" \
  --launchctl-status "$launchctl_status" \
  --stale-threshold-sec "$MAX_BRIDGE_AGE_SECONDS" \
  --idle-threshold-sec "$MAX_PROCESSING_AGE_SECONDS")"

status="$(printf '%s\n' "$_health_output" | awk -F= '/^STATUS=/{print $2}' | tail -1)"
final_status_reason="$(printf '%s\n' "$_health_output" | awk -F= '/^final_status_reason=/{print $2}' | tail -1)"

log_tail="none"
if [ -s "$ERR_LOG" ]; then
  log_tail="present"
fi

echo "plist_exists=$plist_exists"
echo "launchctl_status=$launchctl_status"
echo "process_pid=$process_pid"
echo "signal_dir=$SIGNAL_DIR"
printf '%s\n' "$_health_output"
echo "hook_bridge_health_path=$HEALTH_PATH"
echo "log_tail=$log_tail"
echo "final_status_reason=${final_status_reason:-unknown}"
echo "STATUS=${status:-error}"
