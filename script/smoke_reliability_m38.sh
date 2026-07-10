#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
PROJECTOR_PID=""
cleanup() {
  if [[ -n "$PROJECTOR_PID" ]]; then kill "$PROJECTOR_PID" >/dev/null 2>&1 || true; fi
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

export TASKLIGHT_STATE_DIR="$TMP_ROOT/state"
export TASKLIGHT_NORMALIZED_SIGNALS_PATH="$TASKLIGHT_STATE_DIR/normalized_signals.jsonl"
export TASKLIGHT_SIGNAL_BUS_MAX_BYTES=4096
export TASKLIGHT_HOOK_PENDING_AUTO_RELEASE_SECONDS=5

python3 - "$ROOT_DIR" <<'PY'
import importlib.util
import json
import os
import sys
import time
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "script"))

from check_codex_hooks_trust import summarize
from check_codex_workspaces_coverage import classify_workspace
from state_projector import collapse_visible_tasks, effective_hook_completion_status, runtime_candidate_id
from tasklight_signal_bus import append_signal, compact_signal_bus, signal_bus_path

base = {
    "source": "codex_hook",
    "event_type": "turn_started",
    "thread_id": "thread-one",
    "turn_id": "turn-one",
    "occurred_at": "2026-07-10T00:00:00Z",
    "status_hint": "running",
    "session_id": "session-one",
}
assert runtime_candidate_id(base)[1] == runtime_candidate_id({**base, "turn_id": "turn-two"})[1]

tasks = [
    {"task_id": "a", "visible_identity": "thread:thread-one", "display_scope": "active_execution", "effective_status": "running", "updated_at": "2026-07-10T00:00:01Z"},
    {"task_id": "b", "visible_identity": "thread:thread-one", "display_scope": "active_execution", "effective_status": "running", "updated_at": "2026-07-10T00:00:02Z"},
]
collapsed, duplicate_count = collapse_visible_tasks(tasks)
assert len(collapsed) == 1, collapsed
assert duplicate_count == 1
assert sorted(collapsed[0]["merged_task_ids"]) == ["a", "b"]

payload = {
    "project_root": "ok", "codex_dir": "ok", "hook_config": "ok",
    "hook_reference": "ok", "hook_handler": "ok", "hook_health": "ok",
    "codex_appserver": "unavailable",
}
trust, status, action = summarize(payload)
assert trust == "probe_unavailable", (trust, status, action)
assert status == "probe_unavailable", (trust, status, action)
assert "trust" not in action.lower(), action

coverage = classify_workspace(
    {"hook_status": "probe_unavailable", "hook_detail": "probe_unavailable", "hook_visibility": "probe_unavailable", "codex_appserver": "unavailable"},
    [],
)
assert coverage[0] == "probe_unavailable", coverage
assert "trust" not in coverage[2].lower(), coverage

now = time.time()
assert effective_hook_completion_status("done_unverified", now - 2, now) == "done_unverified"
assert effective_hook_completion_status("done_unverified", now - 6, now) == "cancelled"

append_signal(base)
append_signal(base)
path = signal_bus_path()
compact_signal_bus(path)
rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
ids = [row["signal_id"] for row in rows]
assert len(ids) == 1, ids
assert len(ids) == len(set(ids)), ids
PY

mkdir -p "$TASKLIGHT_STATE_DIR"
TASKLIGHT_STATE_PROJECTOR_POLL_SECONDS=0.2 python3 "$ROOT_DIR/script/state_projector.py" --watch >/dev/null 2>&1 &
PROJECTOR_PID=$!
for _ in $(seq 1 50); do
  [[ -s "$TASKLIGHT_STATE_DIR/ui_state.json" ]] && break
  sleep 0.1
done
[[ -s "$TASKLIGHT_STATE_DIR/ui_state.json" ]]

(cd "$ROOT_DIR/mac/66TaskLight" && swift build --product TaskLightChecks >/dev/null)
CHECKS_BIN="$(cd "$ROOT_DIR/mac/66TaskLight" && swift build --show-bin-path)/TaskLightChecks"
kill "$PROJECTOR_PID"
wait "$PROJECTOR_PID" 2>/dev/null || true
PROJECTOR_PID=""
stopped_at=$(date +%s)
sleep 6
freshness_output="$(TASKLIGHT_PROJECTOR_MAX_AGE_SECONDS=5 TASKLIGHT_CHECK_EXPECTED_FALLBACK=projector_stale "$CHECKS_BIN")"
elapsed=$(( $(date +%s) - stopped_at ))
grep -q 'fallback_reason=projector_stale' <<<"$freshness_output"
(( elapsed <= 10 ))
echo "projector_stale_elapsed_seconds=$elapsed"

echo "smoke_reliability_m38=ok"
