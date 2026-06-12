#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="${TASKLIGHT_APPSERVER_THREAD_WATCHER_LABEL:-com.66tasklight.appserver-thread-watch}"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
LOG_DIR="${TASKLIGHT_APPSERVER_THREAD_WATCHER_LOG_DIR:-$STATE_DIR/logs}"
PLIST_DIR="${TASKLIGHT_APPSERVER_THREAD_WATCHER_PLIST_DIR:-$HOME/Library/LaunchAgents}"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"
PYTHON_BIN="${TASKLIGHT_PYTHON_BIN:-$(command -v python3 || true)}"

if [ -z "$PYTHON_BIN" ]; then
  PYTHON_BIN="/usr/bin/python3"
fi

mkdir -p "$PLIST_DIR" "$STATE_DIR" "$LOG_DIR"
OUT_LOG="$LOG_DIR/appserver_thread_watcher.out.log"
ERR_LOG="$LOG_DIR/appserver_thread_watcher.err.log"

python3 - "$PLIST_PATH" "$LABEL" "$ROOT_DIR" "$STATE_DIR" "$OUT_LOG" "$ERR_LOG" "$PYTHON_BIN" <<'PY'
import os
import plistlib
import sys
from pathlib import Path

plist_path = Path(sys.argv[1])
label = sys.argv[2]
root = Path(sys.argv[3])
state_dir = sys.argv[4]
out_log = sys.argv[5]
err_log = sys.argv[6]
python_bin = sys.argv[7]

payload = {
    "Label": label,
    "ProgramArguments": [
        python_bin,
        str(root / "script" / "appserver_thread_watcher.py"),
        "--watch",
    ],
    "WorkingDirectory": str(root),
    "EnvironmentVariables": {
        "PATH": os.environ.get("PATH", "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"),
        "TASKLIGHT_STATE_DIR": state_dir,
        "TASKLIGHT_APPSERVER_THREAD_WATCHER_POLL_SECONDS": os.environ.get("TASKLIGHT_APPSERVER_THREAD_WATCHER_POLL_SECONDS", "4"),
        "TASKLIGHT_APPSERVER_PROBE_TIMEOUT_SECONDS": os.environ.get("TASKLIGHT_APPSERVER_PROBE_TIMEOUT_SECONDS", "0.6"),
        "TASKLIGHT_APPSERVER_THREAD_ACTIVE_TTL_SECONDS": os.environ.get("TASKLIGHT_APPSERVER_THREAD_ACTIVE_TTL_SECONDS", "12"),
        "TASKLIGHT_APPSERVER_THREAD_COALESCE_SECONDS": os.environ.get("TASKLIGHT_APPSERVER_THREAD_COALESCE_SECONDS", "2"),
        "TASKLIGHT_APPSERVER_THREAD_WATCHER_STATE_PATH": os.environ.get("TASKLIGHT_APPSERVER_THREAD_WATCHER_STATE_PATH", f"{state_dir}/appserver_thread_watcher_state.json"),
        "TASKLIGHT_APPSERVER_THREAD_WATCHER_HEALTH_PATH": os.environ.get("TASKLIGHT_APPSERVER_THREAD_WATCHER_HEALTH_PATH", f"{state_dir}/appserver_thread_watcher_health.json"),
        "TASKLIGHT_NORMALIZED_SIGNALS_PATH": os.environ.get("TASKLIGHT_NORMALIZED_SIGNALS_PATH", f"{state_dir}/normalized_signals.jsonl"),
    },
    "StandardOutPath": out_log,
    "StandardErrorPath": err_log,
    "RunAtLoad": True,
    "KeepAlive": True,
}
plist_path.parent.mkdir(parents=True, exist_ok=True)
with plist_path.open("wb") as handle:
    plistlib.dump(payload, handle, sort_keys=False)
PY

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl enable "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" >/dev/null
launchctl kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
sleep 1

CHECK_OUTPUT="$(TASKLIGHT_APPSERVER_THREAD_WATCHER_LABEL="$LABEL" TASKLIGHT_STATE_DIR="$STATE_DIR" "$ROOT_DIR/script/check_appserver_thread_watcher.sh" || true)"
LAUNCHCTL_STATUS="$(printf '%s\n' "$CHECK_OUTPUT" | awk -F= '/^launchctl_status=/{print $2}' | tail -1)"

echo "plist_path=$PLIST_PATH"
echo "label=$LABEL"
echo "out_log=$OUT_LOG"
echo "err_log=$ERR_LOG"
echo "state_dir=$STATE_DIR"
echo "launchctl_status=${LAUNCHCTL_STATUS:-unknown}"
