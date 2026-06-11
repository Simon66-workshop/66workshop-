#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
SIGNAL_DIR="${TASKLIGHT_SIGNAL_SPOOL_DIR:-$STATE_DIR/signals}"
TURN_BINDINGS_DIR="${TASKLIGHT_TURN_BINDINGS_DIR:-$STATE_DIR/turn_bindings}"
OFFSETS_PATH="${TASKLIGHT_HOOK_BRIDGE_OFFSETS_PATH:-$STATE_DIR/hook_bridge_offsets.json}"

python3 - "$SIGNAL_DIR" "$TURN_BINDINGS_DIR" "$OFFSETS_PATH" <<'PY'
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

signal_dir = Path(sys.argv[1]).expanduser()
bindings_dir = Path(sys.argv[2]).expanduser()
offsets_path = Path(sys.argv[3]).expanduser()

signal_files = sorted(signal_dir.glob("*.jsonl")) if signal_dir.exists() else []
latest_signal_ts = None
for path in signal_files:
    try:
        for line in path.read_text(encoding="utf-8").splitlines()[-20:]:
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
            value = payload.get("event_time")
            try:
                ts = float(value)
            except (TypeError, ValueError):
                continue
            latest_signal_ts = max(latest_signal_ts or ts, ts)
    except OSError:
        pass

active_bindings = 0
if bindings_dir.exists():
    for path in bindings_dir.glob("*.json"):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        if payload.get("status") == "active":
            active_bindings += 1

offsets_status = "missing"
last_run_at = None
last_seen_at = None
if offsets_path.exists():
    offsets_status = "readable"
    try:
        offsets = json.loads(offsets_path.read_text(encoding="utf-8"))
        last_run_at = offsets.get("last_run_at")
        last_seen_at = offsets.get("last_seen_at")
    except (json.JSONDecodeError, OSError):
        offsets_status = "unreadable"

if not signal_files:
    status = "no_signals"
elif offsets_status == "unreadable":
    status = "error"
elif latest_signal_ts and time.time() - latest_signal_ts > 600:
    status = "stale"
else:
    status = "ok"

print(f"signal_dir={signal_dir}")
print(f"signal_file_count={len(signal_files)}")
print(f"latest_signal_time={latest_signal_ts if latest_signal_ts is not None else 'none'}")
print(f"turn_bindings_dir={bindings_dir}")
print(f"active_turn_binding_count={active_bindings}")
print(f"bridge_offsets_path={offsets_path}")
print(f"bridge_offsets_status={offsets_status}")
print(f"last_run_at={last_run_at or 'none'}")
print(f"last_seen_at={last_seen_at or 'none'}")
print(f"status={status}")
PY
