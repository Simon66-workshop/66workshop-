#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "$#" -ne 1 ]; then
  echo "usage: $0 /path/to/workspace" >&2
  exit 2
fi

WORKSPACE="$(cd "$1" && pwd)"
CODEX_DIR="$WORKSPACE/.codex"
HOOKS_PATH="$CODEX_DIR/hooks.json"
CONFIG_PATH="$CODEX_DIR/config.toml"
SPOOL_DIR="${TASKLIGHT_SIGNAL_SPOOL_DIR:-$HOME/.66tasklight/signals}"
HOOK_EVENT="$ROOT_DIR/script/codex_hook_event.py"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$CODEX_DIR" "$SPOOL_DIR"
chmod +x "$HOOK_EVENT"

if [ -f "$HOOKS_PATH" ]; then
  cp "$HOOKS_PATH" "$HOOKS_PATH.bak.$STAMP"
fi
if [ -f "$CONFIG_PATH" ]; then
  cp "$CONFIG_PATH" "$CONFIG_PATH.bak.$STAMP"
fi

hook_command="\"$HOOK_EVENT\" --event-json - --spool-dir \"$SPOOL_DIR\" >/dev/null"

python3 - "$HOOKS_PATH" "$hook_command" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
command = sys.argv[2]

def command_hook(message):
    return {
        "hooks": [
            {
                "type": "command",
                "command": command,
                "timeout": 5,
                "statusMessage": message,
            }
        ]
    }

payload = {
    "hooks": {
        "SessionStart": [{"matcher": "startup|resume", **command_hook("66TaskLight session signal")}],
        "UserPromptSubmit": [command_hook("66TaskLight prompt signal")],
        "PreToolUse": [{"matcher": ".*", **command_hook("66TaskLight tool-start signal")}],
        "PermissionRequest": [command_hook("66TaskLight approval signal")],
        "PostToolUse": [{"matcher": ".*", **command_hook("66TaskLight tool-complete signal")}],
        "Stop": [command_hook("66TaskLight stop signal")],
    }
}
path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

python3 - "$CONFIG_PATH" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8") if path.exists() else ""
lines = text.splitlines()
features_start = None
features_end = len(lines)
for index, line in enumerate(lines):
    if re.match(r"^\s*\[features\]\s*$", line):
        features_start = index
        continue
    if features_start is not None and index > features_start and re.match(r"^\s*\[.+\]\s*$", line):
        features_end = index
        break
if features_start is None:
    if lines and lines[-1].strip():
        lines.append("")
    lines.extend(["[features]", "codex_hooks = true"])
else:
    replaced = False
    for index in range(features_start + 1, features_end):
        if re.match(r"^\s*codex_hooks\s*=", lines[index]):
            lines[index] = "codex_hooks = true"
            replaced = True
            break
    if not replaced:
        lines.insert(features_start + 1, "codex_hooks = true")
path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
PY

echo "workspace_hooks=installed"
echo "workspace=$WORKSPACE"
echo "hooks_path=$HOOKS_PATH"
echo "config_path=$CONFIG_PATH"
echo "signal_spool_dir=$SPOOL_DIR"
"$ROOT_DIR/script/check_codex_thread_coverage.sh" --workspace "$WORKSPACE" --skip-appserver
