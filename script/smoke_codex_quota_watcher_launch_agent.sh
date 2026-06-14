#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-quota-agent-XXXXXX")"
PLIST_DIR="$STATE_DIR/LaunchAgents"
LABEL="com.66tasklight.quota-watcher.smoke"
PLIST="$PLIST_DIR/$LABEL.plist"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_QUOTA_WATCHER_LABEL="$LABEL"
export TASKLIGHT_QUOTA_WATCHER_PLIST="$PLIST"
export TASKLIGHT_QUOTA_WATCH_LOG_DIR="$STATE_DIR/logs"

"$ROOT_DIR/script/install_codex_quota_watcher_launch_agent.sh" --dry-run >/dev/null
test -f "$PLIST"
grep -q "codex_quota_appserver_watcher.py" "$PLIST"
grep -q -- "--watch" "$PLIST"

CHECK_OUTPUT="$("$ROOT_DIR/script/check_codex_quota_watcher_launch_agent.sh")"
printf '%s\n' "$CHECK_OUTPUT" | grep -q "plist_exists=yes"
printf '%s\n' "$CHECK_OUTPUT" | grep -q "STATUS=not_running"

"$ROOT_DIR/script/uninstall_codex_quota_watcher_launch_agent.sh" >/dev/null
test ! -f "$PLIST"

echo "smoke_codex_quota_watcher_launch_agent: ok"
