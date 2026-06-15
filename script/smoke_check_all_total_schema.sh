#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-total-schema-XXXXXX")"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_UI_STATE_PATH="$STATE_DIR/ui_state.json"

cat >"$TASKLIGHT_UI_STATE_PATH" <<'JSON'
{
  "source": "state_projector",
  "schema_version": 3,
  "global_status": "idle",
  "lamp_status": "idle",
  "global_display_title": "IDLE",
  "counts": {
    "running": 0,
    "blocked": 0,
    "pending_verify_count": 0,
    "done_verified_visible": 0,
    "stale": 0,
    "queued": 0
  },
  "tasks": [],
  "diagnostics": {
    "writer_status": "ok"
  }
}
JSON

status_payload="$("$ROOT_DIR/tasklight" status)"
python3 - "$status_payload" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
counts = payload.get("counts") or {}
assert payload["source"] == "state_projector", payload
assert "total" not in counts, counts
assert counts.get("total") is None, counts
assert "compatibility_note" in payload, payload
PY

list_payload="$("$ROOT_DIR/tasklight" list)"
python3 - "$list_payload" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
counts = payload.get("counts") or {}
if "total" not in counts:
    print("tasklight list must expose legacy task counts.total", file=sys.stderr)
    raise SystemExit(1)
assert counts["total"] == 0, counts
PY

echo "smoke_check_all_total_schema: ok"
