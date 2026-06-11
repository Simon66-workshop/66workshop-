#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-observations-XXXXXX")"

cleanup() {
  rm -rf "$STATE_DIR"
}

trap cleanup EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"

python3 - "$ROOT_DIR" <<'PY'
import os
import sys
from pathlib import Path
from unittest.mock import patch

root = Path(sys.argv[1])
sys.path.insert(0, str(root))

from cli.tasklight import TaskLightConfig, TaskLightStore

config = TaskLightConfig.from_env()
store = TaskLightStore(config)
store.ensure_layout()

live_rows = [
    {
        "pid": 100,
        "ppid": 1,
        "uid": os.getuid(),
        "lstart": "Tue Jun 10 11:59:50 2026",
        "command": "/Applications/Codex.app/Contents/MacOS/Codex",
    },
    {
        "pid": 200,
        "ppid": 100,
        "uid": os.getuid(),
        "lstart": "Tue Jun 10 11:59:51 2026",
        "command": "/Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled",
    },
    {
        "pid": 4321,
        "ppid": 200,
        "uid": os.getuid(),
        "lstart": "Tue Jun 10 12:00:00 2026",
        "command": "codex exec smoke-observed-thread",
    },
    {
        "pid": 4322,
        "ppid": 200,
        "uid": os.getuid(),
        "lstart": "Tue Jun 10 12:00:01 2026",
        "command": "codex exec --json --config model_provider=\"openai-memgen\" smoke-observed-thread",
    },
]

cwd_map = {
    4321: "/tmp/codex-observed",
    4322: "/tmp/codex-observed",
}

with patch("cli.tasklight._parse_ps_snapshot", return_value=live_rows), patch(
    "cli.tasklight._process_cwd", side_effect=lambda pid: cwd_map.get(pid)
):
    state = store.observe_local()

assert state.counts.active == 1, state.to_dict()
assert len(state.observations) == 1, state.to_dict()
assert "smoke-observed-thread" in state.observations[0].command, state.to_dict()

with patch("cli.tasklight._parse_ps_snapshot", return_value=[]), patch(
    "cli.tasklight._process_cwd", return_value=None
):
    store.observe_local()
    store.observe_local()
    final_state = store.observe_local()

assert final_state.counts.active == 0, final_state.to_dict()
assert final_state.counts.disappeared == 1, final_state.to_dict()
assert len(final_state.observations) == 0, final_state.to_dict()
PY

echo "smoke_observations: ok"
