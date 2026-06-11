#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
SIGNAL_DIR="${TASKLIGHT_SIGNAL_SPOOL_DIR:-$STATE_DIR/signals}"
TURN_BINDINGS_DIR="${TASKLIGHT_TURN_BINDINGS_DIR:-$STATE_DIR/turn_bindings}"
OFFSETS_PATH="${TASKLIGHT_HOOK_BRIDGE_OFFSETS_PATH:-$STATE_DIR/hook_bridge_offsets.json}"
HEALTH_PATH="${TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH:-$STATE_DIR/hook_bridge_health.json}"

python3 - "$SIGNAL_DIR" "$TURN_BINDINGS_DIR" "$OFFSETS_PATH" "$HEALTH_PATH" <<'PY'
from __future__ import annotations

import json
import sys
import time
from datetime import datetime
from pathlib import Path

signal_dir = Path(sys.argv[1]).expanduser()
bindings_dir = Path(sys.argv[2]).expanduser()
offsets_path = Path(sys.argv[3]).expanduser()
health_path = Path(sys.argv[4]).expanduser()


def parse_ts(value):
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value))
    except ValueError:
        pass
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


signal_files = sorted(signal_dir.glob("*.jsonl")) if signal_dir.exists() else []
latest_signal_ts = None
latest_stop_signal_ts = None
for path in signal_files:
    try:
        for line in path.read_text(encoding="utf-8").splitlines()[-20:]:
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
            ts = parse_ts(payload.get("event_time"))
            if ts is not None:
                latest_signal_ts = max(latest_signal_ts or ts, ts)
                if payload.get("event_type") == "stop":
                    latest_stop_signal_ts = max(latest_stop_signal_ts or ts, ts)
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
stop_diagnostics = {}
if offsets_path.exists():
    offsets_status = "readable"
    try:
        offsets = json.loads(offsets_path.read_text(encoding="utf-8"))
        last_run_at = offsets.get("last_run_at")
        last_seen_at = offsets.get("last_seen_at")
        stop_diagnostics = offsets.get("stop_diagnostics") if isinstance(offsets.get("stop_diagnostics"), dict) else {}
    except (json.JSONDecodeError, OSError):
        offsets_status = "unreadable"

health_status = "missing"
health = {}
if health_path.exists():
    try:
        health = json.loads(health_path.read_text(encoding="utf-8"))
        health_status = "readable"
    except (json.JSONDecodeError, OSError):
        health_status = "unreadable"

if health_status == "readable":
    status = str(health.get("status") or "ok")
elif not signal_files:
    status = "no_signals"
elif offsets_status == "unreadable" or health_status == "unreadable":
    status = "error"
elif latest_signal_ts and time.time() - latest_signal_ts > 600:
    status = "stale"
else:
    status = "ok"

print(f"signal_dir={signal_dir}")
print(f"signal_file_count={len(signal_files)}")
print(f"latest_signal_time={latest_signal_ts if latest_signal_ts is not None else 'none'}")
print(f"latest_stop_signal_age_sec={int(time.time() - latest_stop_signal_ts) if latest_stop_signal_ts is not None else 'none'}")
print(f"turn_bindings_dir={bindings_dir}")
print(f"active_turn_binding_count={active_bindings}")
print(f"bridge_offsets_path={offsets_path}")
print(f"bridge_offsets_status={offsets_status}")
print(f"hook_bridge_health_path={health_path}")
print(f"hook_bridge_health_status={health_status}")
print(f"hook_bridge_health_state={health.get('status', 'none') if health_status == 'readable' else 'none'}")
print(f"latest_stop_decision={health.get('latest_stop_decision') or stop_diagnostics.get('latest_stop_decision') or 'none'}")
print(f"late_stop_recovered_count={health.get('late_stop_recovered_count', stop_diagnostics.get('late_stop_recovered_count', 0))}")
print(f"soft_release_count={health.get('soft_release_count', stop_diagnostics.get('soft_release_count', 0))}")
print(f"stop_ignored_count={health.get('stop_ignored_count', stop_diagnostics.get('stop_ignored_count', 0))}")
print(f"last_run_at={health.get('last_run_at') or last_run_at or 'none'}")
print(f"last_seen_at={health.get('last_seen_at') or last_seen_at or 'none'}")
print(f"status={status}")
PY
