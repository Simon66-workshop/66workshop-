#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-signal-bus-XXXXXX")"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_NORMALIZED_SIGNALS_PATH="$STATE_DIR/normalized_signals.jsonl"
export TASKLIGHT_UI_STATE_PATH="$STATE_DIR/ui_state.json"
export TASKLIGHT_STATE_PROJECTOR_HEALTH_PATH="$STATE_DIR/state_projector_health.json"
export TASKLIGHT_SIGNAL_BUS_MAX_BYTES=8192
export TASKLIGHT_SIGNAL_BUS_MAX_RECORDS=12
export TASKLIGHT_SIGNAL_BUS_RETENTION_SECONDS=86400
export PYTHONPATH="$ROOT_DIR/script${PYTHONPATH:+:$PYTHONPATH}"

mkdir -p "$STATE_DIR/tasks" "$STATE_DIR/turn_bindings"

for index in $(seq 1 20); do
  python3 - "$index" <<'PY' &
import sys
from tasklight_signal_bus import append_signal

index = int(sys.argv[1])
append_signal(
    {
        "source": "explicit",
        "event_type": "heartbeat",
        "task_id": f"parallel-{index}",
        "occurred_at": f"2099-01-01T00:00:{index:02d}Z",
        "confidence": 0.98,
        "source_quality": "signal_bus_smoke",
        "evidence": [f"parallel={index}"],
        "conflicts": [],
        "status_hint": "running",
    }
)
PY
done
wait

python3 - "$TASKLIGHT_NORMALIZED_SIGNALS_PATH" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
assert 12 <= len(lines) <= 20, len(lines)
for line in lines:
    payload = json.loads(line)
    assert isinstance(payload, dict), payload
    assert payload["signal_id"].startswith("sig_"), payload
PY

export TASKLIGHT_SIGNAL_BUS_MAX_BYTES=512

for index in $(seq 21 80); do
  python3 - "$index" <<'PY'
import sys
from tasklight_signal_bus import append_signal

index = int(sys.argv[1])
append_signal(
    {
        "source": "explicit",
        "event_type": "heartbeat",
        "task_id": f"compact-{index}",
        "occurred_at": f"2099-01-01T00:01:{index % 60:02d}Z",
        "confidence": 0.98,
        "source_quality": "signal_bus_smoke",
        "evidence": ["compaction"],
        "conflicts": [],
        "status_hint": "running",
    }
)
PY
done

python3 - "$TASKLIGHT_NORMALIZED_SIGNALS_PATH" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = [line for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
assert len(lines) <= 12, len(lines)
for line in lines:
    payload = json.loads(line)
    assert payload["source"] == "explicit" or payload["source"] == "codex_hook", payload
PY

python3 - "$STATE_DIR/turn_bindings/hook_unknown_turn-signal.json" <<'PY'
import json
import sys
from pathlib import Path

binding_path = Path(sys.argv[1])
binding_path.write_text(json.dumps({
    "schema_version": "0.1",
    "source_key": "hook:unknown:turn-signal",
    "canonical_identity": "turn:turn-signal",
    "aliases": ["appserver:thread-a:turn-signal"],
    "task_id": "signal-hook",
    "thread_id": "thread-a",
    "turn_id": "turn-signal",
    "origin_signal_id": "sig-hook-running",
    "title": "Codex turn signal",
    "cwd": "/tmp/signal-bus",
    "status": "active",
    "phase": "tool_running",
    "last_signal_event": "item_started",
    "last_signal_at": "2099-01-01T00:00:00Z",
    "created_at": "2099-01-01T00:00:00Z",
    "updated_at": "2099-01-01T00:00:00Z",
    "signal_count": 1
}, sort_keys=True), encoding="utf-8")
PY

python3 - <<'PY'
from tasklight_signal_bus import append_signal

append_signal(
    {
        "signal_id": "sig-hook-running",
        "source": "codex_hook",
        "event_type": "item_started",
        "thread_id": "thread-a",
        "turn_id": "turn-signal",
        "task_id": "signal-hook",
        "occurred_at": "2099-01-01T00:00:01Z",
        "confidence": 0.95,
        "thread_scoped": True,
        "turn_scoped": True,
        "source_quality": "signal_bus_smoke",
        "evidence": ["turn-running"],
        "conflicts": [],
        "status_hint": "running",
    }
)
PY

python3 "$ROOT_DIR/script/state_projector.py" --once >/dev/null

python3 - "$STATE_DIR/ui_state.json" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert payload["global_status"] == "running", payload
assert payload["diagnostics"]["signal_bus_status"] == "readable", payload
task = next(item for item in payload["tasks"] if item["task_id"] == "signal-hook")
assert task["turn_id"] == "turn-signal", task
assert task["display_scope"] == "active_execution", task
assert task["source"] in {"codex_hook", "signal_bus", "hook_bridge"}, task
PY

echo "smoke_signal_bus: ok"
