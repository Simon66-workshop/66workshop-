#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="${TASKLIGHT_QUOTA_WATCHER_LABEL:-com.66tasklight.quota-watcher}"
PLIST_PATH="${TASKLIGHT_QUOTA_WATCHER_PLIST:-$HOME/Library/LaunchAgents/${LABEL}.plist}"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
LOG_DIR="${TASKLIGHT_QUOTA_WATCH_LOG_DIR:-$STATE_DIR/logs}"
PYTHON_BIN="${PYTHON_BIN:-$(command -v python3)}"
POLL_SECONDS="${TASKLIGHT_QUOTA_WATCH_POLL_SECONDS:-10}"
EVENT_TIMEOUT="${TASKLIGHT_QUOTA_WATCH_EVENT_TIMEOUT_SECONDS:-1.5}"
REQUEST_TIMEOUT="${TASKLIGHT_QUOTA_AUTOPROBE_TIMEOUT_SECONDS:-5}"
CODEX_BIN="${TASKLIGHT_CODEX_BIN:-${CODEX_BIN:-}}"
DRY_RUN=0

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

mkdir -p "$(dirname "$PLIST_PATH")" "$LOG_DIR" "$STATE_DIR"
"$ROOT_DIR/script/stage_tasklight_runtime.sh" --state-dir "$STATE_DIR" >/dev/null
RUNTIME_ROOT="${TASKLIGHT_RUNTIME_ROOT:-$STATE_DIR/runtime/tasklight-python}"
RUNTIME_SCRIPT="$RUNTIME_ROOT/script/codex_quota_appserver_watcher.py"

if [[ -z "$CODEX_BIN" ]]; then
  for candidate in \
    "/Applications/ChatGPT.app/Contents/Resources/codex" \
    "/Applications/Codex.app/Contents/Resources/codex" \
    "$(command -v codex 2>/dev/null || true)"
  do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      CODEX_BIN="$candidate"
      break
    fi
  done
fi

cat >"$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>WorkingDirectory</key>
  <string>${RUNTIME_ROOT}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${PYTHON_BIN}</string>
    <string>${RUNTIME_SCRIPT}</string>
    <string>--watch</string>
    <string>--poll-seconds</string>
    <string>${POLL_SECONDS}</string>
    <string>--event-timeout</string>
    <string>${EVENT_TIMEOUT}</string>
    <string>--timeout</string>
    <string>${REQUEST_TIMEOUT}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>TASKLIGHT_STATE_DIR</key>
    <string>${STATE_DIR}</string>
    <key>CODEX_BIN</key>
    <string>${CODEX_BIN}</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/quota_watcher.out.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/quota_watcher.err.log</string>
</dict>
</plist>
PLIST

if [[ "$DRY_RUN" == "0" ]]; then
  launchctl bootout "gui/$UID" "$PLIST_PATH" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$UID" "$PLIST_PATH"
  launchctl kickstart -k "gui/$UID/$LABEL" >/dev/null 2>&1 || true
fi

echo "plist_path=$PLIST_PATH"
echo "label=$LABEL"
echo "state_dir=$STATE_DIR"
echo "log_dir=$LOG_DIR"
if [[ "$DRY_RUN" == "1" ]]; then
  echo "launchctl_status=dry_run"
else
  "$ROOT_DIR/script/check_codex_quota_watcher_launch_agent.sh" || true
fi
