#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="${TASKLIGHT_STATE_PROJECTOR_LABEL:-com.66tasklight.state-projector}"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
LOG_DIR="${TASKLIGHT_STATE_PROJECTOR_LOG_DIR:-$STATE_DIR/logs}"
PLIST_DIR="${TASKLIGHT_STATE_PROJECTOR_PLIST_DIR:-$HOME/Library/LaunchAgents}"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"
PYTHON_BIN="${PYTHON_BIN:-$(command -v python3)}"

mkdir -p "$PLIST_DIR" "$LOG_DIR" "$STATE_DIR"

python3 - "$PLIST_PATH" "$LABEL" "$ROOT_DIR" "$STATE_DIR" "$LOG_DIR" "$PYTHON_BIN" <<'PY'
import plistlib
import sys
from pathlib import Path

plist_path = Path(sys.argv[1])
label = sys.argv[2]
root = Path(sys.argv[3])
state_dir = sys.argv[4]
log_dir = Path(sys.argv[5])
python_bin = sys.argv[6]

payload = {
    "Label": label,
    "ProgramArguments": [
        python_bin,
        str(root / "script" / "state_projector.py"),
        "--watch",
    ],
    "WorkingDirectory": str(root),
    "EnvironmentVariables": {
        "TASKLIGHT_STATE_DIR": state_dir,
        "TASKLIGHT_UI_STATE_PATH": f"{state_dir}/ui_state.json",
        "TASKLIGHT_STATE_PROJECTOR_HEALTH_PATH": f"{state_dir}/state_projector_health.json",
        "TASKLIGHT_NORMALIZED_SIGNALS_PATH": f"{state_dir}/normalized_signals.jsonl",
    },
    "StandardOutPath": str(log_dir / "state_projector.out.log"),
    "StandardErrorPath": str(log_dir / "state_projector.err.log"),
    "RunAtLoad": True,
    "KeepAlive": True,
}
plist_path.write_bytes(plistlib.dumps(payload, sort_keys=True))
PY

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl enable "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
sleep 1

echo "plist_path=$PLIST_PATH"
echo "label=$LABEL"
echo "out_log=$LOG_DIR/state_projector.out.log"
echo "err_log=$LOG_DIR/state_projector.err.log"
echo "state_dir=$STATE_DIR"
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  echo "launchctl_status=running"
else
  echo "launchctl_status=not_running"
fi
