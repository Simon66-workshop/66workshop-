#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="${TASKLIGHT_OBSERVER_LABEL:-com.local.66tasklight.observer}"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
OBSERVER_MATCH="${TASKLIGHT_OBSERVER_MATCH:-observe-local --watch}"
LOG_PATH="${TASKLIGHT_OBSERVER_LOG_PATH:-$STATE_DIR/observer.log}"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"

mkdir -p "$PLIST_DIR" "$STATE_DIR"

OBSERVER_MATCH_ARG="$OBSERVER_MATCH"
PYTHON_BIN="${TASKLIGHT_PYTHON_BIN:-$(command -v python3 || true)}"
if [ -z "$PYTHON_BIN" ]; then
  PYTHON_BIN="/usr/bin/python3"
fi
PYTHON_BIN_Q="$(printf "%s" "$PYTHON_BIN" | sed "s/'/'\\\\''/g")"
ROOT_DIR_Q="$(printf "%s" "$ROOT_DIR" | sed "s/'/'\\\\''/g")"
STATE_DIR_Q="$(printf "%s" "$STATE_DIR" | sed "s/'/'\\\\''/g")"

cat >"$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-lc</string>
    <string>export TASKLIGHT_STATE_DIR=$STATE_DIR_Q; exec -a '$OBSERVER_MATCH' $PYTHON_BIN_Q '$ROOT_DIR_Q/cli/tasklight.py' observe-local --watch</string>
    <string>$OBSERVER_MATCH_ARG</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>TASKLIGHT_STATE_DIR</key>
    <string>$STATE_DIR</string>
    <key>TASKLIGHT_REFRESH_SECONDS</key>
    <string>${TASKLIGHT_REFRESH_SECONDS:-1}</string>
    <key>TASKLIGHT_OBSERVATIONS_STATE_PATH</key>
    <string>$STATE_DIR/observations_state.json</string>
    <key>TASKLIGHT_OBSERVATIONS_DIR</key>
    <string>$STATE_DIR/observations</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_PATH</string>
  <key>StandardErrorPath</key>
  <string>$LOG_PATH</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl enable "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" >/dev/null
launchctl kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true

sleep 0.5

TASKLIGHT_OBSERVER_MATCH="$OBSERVER_MATCH" TASKLIGHT_STATE_DIR="$STATE_DIR" "$ROOT_DIR/script/check_observer.sh" >/dev/null

echo "plist_path=$PLIST_PATH"
echo "log_path=$LOG_PATH"
echo "state_dir=$STATE_DIR"
echo "observer_watch_status=running"
