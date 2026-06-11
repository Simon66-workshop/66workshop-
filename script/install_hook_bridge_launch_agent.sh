#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="${TASKLIGHT_HOOK_BRIDGE_LABEL:-com.66tasklight.hook-bridge}"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
LOG_DIR="${TASKLIGHT_HOOK_BRIDGE_LOG_DIR:-$STATE_DIR/logs}"
PLIST_DIR="${TASKLIGHT_HOOK_BRIDGE_PLIST_DIR:-$HOME/Library/LaunchAgents}"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"
PYTHON_BIN="${TASKLIGHT_PYTHON_BIN:-$(command -v python3 || true)}"

if [ -z "$PYTHON_BIN" ]; then
  PYTHON_BIN="/usr/bin/python3"
fi

mkdir -p "$PLIST_DIR" "$STATE_DIR" "$LOG_DIR"

OUT_LOG="$LOG_DIR/hook_bridge.out.log"
ERR_LOG="$LOG_DIR/hook_bridge.err.log"

python3 - "$PLIST_PATH" "$LABEL" "$PYTHON_BIN" "$ROOT_DIR" "$STATE_DIR" "$OUT_LOG" "$ERR_LOG" <<'PY'
from __future__ import annotations

import os
import plistlib
import sys
from pathlib import Path

plist_path = Path(sys.argv[1])
label = sys.argv[2]
python_bin = sys.argv[3]
root_dir = sys.argv[4]
state_dir = sys.argv[5]
out_log = sys.argv[6]
err_log = sys.argv[7]

env = {
    "PATH": os.environ.get("PATH", "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"),
    "TASKLIGHT_STATE_DIR": state_dir,
    "TASKLIGHT_SIGNAL_SPOOL_DIR": os.environ.get("TASKLIGHT_SIGNAL_SPOOL_DIR", f"{state_dir}/signals"),
    "TASKLIGHT_TURN_BINDINGS_DIR": os.environ.get("TASKLIGHT_TURN_BINDINGS_DIR", f"{state_dir}/turn_bindings"),
    "TASKLIGHT_HOOK_BRIDGE_OFFSETS_PATH": os.environ.get("TASKLIGHT_HOOK_BRIDGE_OFFSETS_PATH", f"{state_dir}/hook_bridge_offsets.json"),
    "TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH": os.environ.get("TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH", f"{state_dir}/hook_bridge_health.json"),
    "TASKLIGHT_HOOK_TURN_LEASE_SECONDS": os.environ.get("TASKLIGHT_HOOK_TURN_LEASE_SECONDS", "60"),
    "TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS": os.environ.get("TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS", "6"),
    "TASKLIGHT_HOOK_BRIDGE_POLL_SECONDS": os.environ.get("TASKLIGHT_HOOK_BRIDGE_POLL_SECONDS", "1"),
    "TASKLIGHT_HOOK_BRIDGE_COALESCE_SECONDS": os.environ.get("TASKLIGHT_HOOK_BRIDGE_COALESCE_SECONDS", "2"),
    "TASKLIGHT_HOOK_SIGNAL_MAX_AGE_SECONDS": os.environ.get("TASKLIGHT_HOOK_SIGNAL_MAX_AGE_SECONDS", "600"),
}

payload = {
    "Label": label,
    "ProgramArguments": [
        python_bin,
        f"{root_dir}/script/hook_signal_bridge.py",
        "--watch",
    ],
    "WorkingDirectory": root_dir,
    "EnvironmentVariables": env,
    "RunAtLoad": True,
    "KeepAlive": True,
    "StandardOutPath": out_log,
    "StandardErrorPath": err_log,
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

CHECK_OUTPUT="$(TASKLIGHT_HOOK_BRIDGE_LABEL="$LABEL" TASKLIGHT_STATE_DIR="$STATE_DIR" TASKLIGHT_HOOK_BRIDGE_LOG_DIR="$LOG_DIR" "$ROOT_DIR/script/check_hook_bridge_launch_agent.sh" || true)"
LAUNCHCTL_STATUS="$(printf '%s\n' "$CHECK_OUTPUT" | awk -F= '/^launchctl_status=/{print $2}' | tail -1)"

echo "plist_path=$PLIST_PATH"
echo "label=$LABEL"
echo "out_log=$OUT_LOG"
echo "err_log=$ERR_LOG"
echo "state_dir=$STATE_DIR"
echo "launchctl_status=${LAUNCHCTL_STATUS:-unknown}"
