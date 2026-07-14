#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-storage-lifecycle-XXXXXX")"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

python3 - "$STATE_DIR" <<'PY'
import json
import os
import sys
import time
from pathlib import Path

root = Path(sys.argv[1])
tasks = root / "tasks"
tasks.mkdir(parents=True)
old = time.time() - 45 * 86400
records = {
    "active": {"task_id": "active", "status": "running", "updated_at": "2020-01-01T00:00:00Z"},
    "blocked": {"task_id": "blocked", "status": "blocked", "updated_at": "2020-01-01T00:00:00Z"},
    "pending": {"task_id": "pending", "status": "done_unverified", "updated_at": "2020-01-01T00:00:00Z"},
    "done": {"task_id": "done", "status": "done_verified", "updated_at": "2020-01-01T00:00:00Z"},
    "cancelled": {"task_id": "cancelled", "status": "cancelled", "updated_at": "2020-01-01T00:00:00Z"},
}
for name, payload in records.items():
    path = tasks / f"{name}.json"
    path.write_text(json.dumps(payload) + "\n", encoding="utf-8")
    os.utime(path, (old, old))
PY

TMP_REPORT="$STATE_DIR/report.json"
python3 "$ROOT_DIR/script/tasklight_storage_audit.py" --state-dir "$STATE_DIR" --project-root "$ROOT_DIR" --output-json "$TMP_REPORT" --output-md "$STATE_DIR/report.md" >/dev/null
[ "$(jq '.directories.tasks.file_count' "$TMP_REPORT")" -eq 5 ]

python3 "$ROOT_DIR/script/tasklight_storage_maintenance.py" --state-dir "$STATE_DIR" --report-only --keep-recent 0 --older-than-days 30 --output-json "$STATE_DIR/dry.json" >/dev/null
[ "$(jq -r '.mode' "$STATE_DIR/dry.json")" = "report_only" ]
[ "$(find "$STATE_DIR/tasks" -type f -name '*.json' | wc -l | tr -d ' ')" -eq 5 ]

python3 "$ROOT_DIR/script/tasklight_storage_maintenance.py" --state-dir "$STATE_DIR" --apply --keep-recent 0 --older-than-days 30 --output-json "$STATE_DIR/apply.json" >/dev/null
[ -f "$STATE_DIR/tasks/active.json" ]
[ -f "$STATE_DIR/tasks/blocked.json" ]
[ -f "$STATE_DIR/tasks/pending.json" ]
[ -f "$STATE_DIR/archive/tasks/2020-01/done.json" ]
[ -f "$STATE_DIR/archive/tasks/2020-01/cancelled.json" ]
echo "smoke_storage_lifecycle=ok"
