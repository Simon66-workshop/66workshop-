#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-large-state-XXXXXX")"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

python3 - "$STATE_DIR" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
tasks = root / "tasks"
bindings = root / "turn_bindings"
clients = root / "ui_clients"
tasks.mkdir(parents=True)
bindings.mkdir(parents=True)
clients.mkdir(parents=True)
for index in range(10000):
    status = "running" if index == 0 else "done_verified"
    payload = {
        "task_id": f"fixture-{index}",
        "title": "large-state-fixture",
        "slug": "large-state-fixture",
        "status": status,
        "effective_status": status,
        "raw_status": status,
        "updated_at": "2026-07-13T00:00:00Z",
        "heartbeat_at": "2026-07-13T00:00:00Z",
    }
    (tasks / f"fixture-{index}.json").write_text(json.dumps(payload) + "\n", encoding="utf-8")
for index in range(3000):
    (bindings / f"binding-{index}.json").write_text(json.dumps({"status": "released", "task_id": f"fixture-{index}"}) + "\n", encoding="utf-8")
for index in range(1000):
    (clients / f"{index}.json").write_text(json.dumps({"pid": index, "updated_at": "2020-01-01T00:00:00Z"}) + "\n", encoding="utf-8")
state = {
    "schema_version": 3,
    "source": "tasklight",
    "source_health": "healthy",
    "global_status": "running",
    "lamp_status": "running",
    "counts": {"running": 1, "total": 1, "active": 1, "blue": 1},
    "tasks": [json.loads((tasks / "fixture-0.json").read_text())],
    "invalid_tasks": [],
}
(root / "state.json").write_text(json.dumps(state) + "\n", encoding="utf-8")
(root / "events.jsonl").write_bytes(b"{}\n" * (20 * 1024 * 1024 // 3))
PY

start=$(python3 -c 'import time; print(time.monotonic())')
TASKLIGHT_STATE_DIR="$STATE_DIR" "$ROOT_DIR/tasklight" heartbeat --task-id fixture-0 --phase large_fixture --progress 0.5 >/dev/null
elapsed=$(python3 - "$start" <<'PY'
import sys, time
print(round(time.monotonic() - float(sys.argv[1]), 3))
PY
)
python3 - "$elapsed" <<'PY'
import sys
elapsed = float(sys.argv[1])
assert elapsed < 5.0, elapsed
PY

start=$(python3 -c 'import time; print(time.monotonic())')
start_json="$(TASKLIGHT_STATE_DIR="$STATE_DIR" "$ROOT_DIR/tasklight" start --title large_fixture_new)"
start_elapsed=$(python3 - "$start" <<'PY'
import sys, time
print(round(time.monotonic() - float(sys.argv[1]), 3))
PY
)
python3 - "$start_elapsed" <<'PY'
import sys
elapsed = float(sys.argv[1])
assert elapsed < 5.0, elapsed
PY

new_task_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["task_id"])' <<<"$start_json")"
start=$(python3 -c 'import time; print(time.monotonic())')
TASKLIGHT_STATE_DIR="$STATE_DIR" "$ROOT_DIR/tasklight" release --task-id "$new_task_id" >/dev/null
release_elapsed=$(python3 - "$start" <<'PY'
import sys, time
print(round(time.monotonic() - float(sys.argv[1]), 3))
PY
)
python3 - "$release_elapsed" <<'PY'
import sys
elapsed = float(sys.argv[1])
assert elapsed < 5.0, elapsed
PY
echo "smoke_large_state_render_performance=ok heartbeat_seconds=$elapsed start_seconds=$start_elapsed release_seconds=$release_elapsed"
