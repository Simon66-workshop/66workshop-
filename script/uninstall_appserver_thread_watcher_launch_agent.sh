#!/usr/bin/env bash
set -euo pipefail

LABEL="${TASKLIGHT_APPSERVER_THREAD_WATCHER_LABEL:-com.66tasklight.appserver-thread-watch}"
PLIST_DIR="${TASKLIGHT_APPSERVER_THREAD_WATCHER_PLIST_DIR:-$HOME/Library/LaunchAgents}"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl disable "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"

echo "plist_path=$PLIST_PATH"
echo "label=$LABEL"
echo "launchctl_status=not_running"
