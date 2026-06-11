#!/usr/bin/env bash
set -euo pipefail

LABEL="${TASKLIGHT_STATE_PROJECTOR_LABEL:-com.66tasklight.state-projector}"
PLIST_DIR="${TASKLIGHT_STATE_PROJECTOR_PLIST_DIR:-$HOME/Library/LaunchAgents}"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl disable "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"

echo "plist_path=$PLIST_PATH"
echo "label=$LABEL"
echo "launchctl_status=not_running"
