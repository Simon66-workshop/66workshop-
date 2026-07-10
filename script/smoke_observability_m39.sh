#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
STATE_DIR="$TMP_ROOT/state"
mkdir -p "$STATE_DIR"

cat >"$STATE_DIR/normalized_signals.jsonl" <<'JSONL'
{"signal_id":"one","source":"codex_hook","event_type":"turn_started","thread_id":"thread-a","occurred_at":"2026-07-10T00:00:00Z","status_hint":"running"}
{"signal_id":"one","source":"codex_hook","event_type":"turn_started","thread_id":"thread-a","occurred_at":"2026-07-10T00:00:00Z","status_hint":"running"}
{"signal_id":"two","source":"codex_hook","event_type":"turn_completed","thread_id":"thread-a","occurred_at":"2026-07-10T00:00:01Z","status_hint":"done_unverified"}
JSONL
cat >"$STATE_DIR/ui_event_flow.jsonl" <<'JSONL'
{"event_id":"ui-1","recorded_at":"2026-07-10T00:00:00Z","from_status":"idle","to_status":"running"}
{"event_id":"ui-2","recorded_at":"2026-07-10T00:00:01Z","from_status":"running","to_status":"idle"}
JSONL

TASKLIGHT_STATE_DIR="$STATE_DIR" python3 "$ROOT_DIR/script/tasklight_history_index.py" --once >/dev/null

python3 - "$STATE_DIR" <<'PY'
import json
import sqlite3
import sys
from pathlib import Path

root = Path(sys.argv[1])
summary = json.loads((root / "anomaly_summary.json").read_text())
assert summary["history_row_count"] == 4, summary
assert summary["duplicate_signal_rate"] > 0, summary
assert summary["duplicate_signal_rate"] < 1, summary
db = sqlite3.connect(root / "history.sqlite3")
assert db.execute("select count(*) from history").fetchone()[0] == 4
assert db.execute("pragma journal_mode").fetchone()[0].lower() == "wal"
db.close()
PY

echo "smoke_observability_m39=ok"
