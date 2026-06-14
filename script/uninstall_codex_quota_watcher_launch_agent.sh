#!/usr/bin/env bash
set -euo pipefail

LABEL="${TASKLIGHT_QUOTA_WATCHER_LABEL:-com.66tasklight.quota-watcher}"
PLIST_PATH="${TASKLIGHT_QUOTA_WATCHER_PLIST:-$HOME/Library/LaunchAgents/${LABEL}.plist}"

launchctl bootout "gui/$UID" "$PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"

echo "plist_path=$PLIST_PATH"
echo "label=$LABEL"
echo "launchctl_status=not_running"
echo "STATUS=not_running"
