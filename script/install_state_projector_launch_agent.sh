#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="${TASKLIGHT_STATE_PROJECTOR_LABEL:-com.66tasklight.state-projector}"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
LOG_DIR="${TASKLIGHT_STATE_PROJECTOR_LOG_DIR:-$STATE_DIR/logs}"
PLIST_DIR="${TASKLIGHT_STATE_PROJECTOR_PLIST_DIR:-$HOME/Library/LaunchAgents}"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"
PYTHON_BIN="${TASKLIGHT_PYTHON_BIN:-$(command -v python3 || true)}"

if [ -z "$PYTHON_BIN" ]; then
  PYTHON_BIN="/usr/bin/python3"
fi

mkdir -p "$PLIST_DIR" "$LOG_DIR" "$STATE_DIR"
OUT_LOG="$LOG_DIR/state_projector.out.log"
ERR_LOG="$LOG_DIR/state_projector.err.log"
"$ROOT_DIR/script/stage_tasklight_runtime.sh" --state-dir "$STATE_DIR" >/dev/null
RUNTIME_ROOT="${TASKLIGHT_RUNTIME_ROOT:-$STATE_DIR/runtime/tasklight-python}"
RUNTIME_SCRIPT="$RUNTIME_ROOT/script/state_projector.py"

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
pkill -f "$ROOT_DIR/script/state_projector.py --watch" >/dev/null 2>&1 || true
pkill -f "$RUNTIME_SCRIPT --watch" >/dev/null 2>&1 || true

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
        str(Path(state_dir) / "runtime" / "tasklight-python" / "script" / "state_projector.py"),
        "--watch",
    ],
    "WorkingDirectory": str(Path(state_dir) / "runtime" / "tasklight-python"),
    "EnvironmentVariables": {
        "PATH": os.environ.get("PATH", "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"),
        "TASKLIGHT_STATE_DIR": state_dir,
        "TASKLIGHT_UI_STATE_PATH": f"{state_dir}/ui_state.json",
        "TASKLIGHT_STATE_PROJECTOR_HEALTH_PATH": f"{state_dir}/state_projector_health.json",
        "TASKLIGHT_NORMALIZED_SIGNALS_PATH": f"{state_dir}/normalized_signals.jsonl",
        "TASKLIGHT_STATE_PROJECTOR_POLL_SECONDS": os.environ.get("TASKLIGHT_STATE_PROJECTOR_POLL_SECONDS", "1"),
        "TASKLIGHT_HOOK_ACTIVE_DISPLAY_TTL_SECONDS": os.environ.get("TASKLIGHT_HOOK_ACTIVE_DISPLAY_TTL_SECONDS", "12"),
        "TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS": os.environ.get("TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS", "20"),
        "TASKLIGHT_HOOK_TURN_LEASE_SECONDS": os.environ.get("TASKLIGHT_HOOK_TURN_LEASE_SECONDS", "60"),
        "TASKLIGHT_OBSERVED_ACTIVE_TTL_SECONDS": os.environ.get("TASKLIGHT_OBSERVED_ACTIVE_TTL_SECONDS", "8"),
        "TASKLIGHT_DONE_VISIBLE_HOURS": os.environ.get("TASKLIGHT_DONE_VISIBLE_HOURS", "24"),
        "TASKLIGHT_STATE_PROJECTOR_LABEL": label,
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

launchctl enable "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" >/dev/null
launchctl kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
sleep 2

CHECK_OUTPUT="$(TASKLIGHT_STATE_PROJECTOR_LABEL="$LABEL" TASKLIGHT_STATE_DIR="$STATE_DIR" "$ROOT_DIR/script/check_state_projector.sh" || true)"
LAUNCHCTL_STATUS="$(printf '%s\n' "$CHECK_OUTPUT" | awk -F= '/^launchctl_status=/{print $2}' | tail -1)"
PROJECTOR_PID="$(printf '%s\n' "$CHECK_OUTPUT" | awk -F= '/^projector_pid=/{print $2}' | tail -1)"
PROJECTOR_VERSION="$(printf '%s\n' "$CHECK_OUTPUT" | awk -F= '/^projector_version=/{print $2}' | tail -1)"
PROJECTOR_HASH="$(printf '%s\n' "$CHECK_OUTPUT" | awk -F= '/^projector_code_hash=/{print $2}' | tail -1)"
EXPECTED_HASH="$(printf '%s\n' "$CHECK_OUTPUT" | awk -F= '/^expected_code_hash=/{print $2}' | tail -1)"
WRITER_STATUS="$(printf '%s\n' "$CHECK_OUTPUT" | awk -F= '/^writer_status=/{print $2}' | tail -1)"

echo "plist_path=$PLIST_PATH"
echo "label=$LABEL"
echo "out_log=$OUT_LOG"
echo "err_log=$ERR_LOG"
echo "state_dir=$STATE_DIR"
echo "launchctl_status=${LAUNCHCTL_STATUS:-unknown}"
echo "projector_pid=${PROJECTOR_PID:-unknown}"
echo "projector_version=${PROJECTOR_VERSION:-unknown}"
echo "projector_code_hash=${PROJECTOR_HASH:-unknown}"
echo "expected_code_hash=${EXPECTED_HASH:-unknown}"
echo "writer_status=${WRITER_STATUS:-unknown}"
