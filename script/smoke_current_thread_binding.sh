#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/script/codex_current_task.sh"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-thread-binding-XXXXXX")"
THREAD_ID="smoke-thread-$(date +%s)"

cleanup() {
  if [[ -n "${WATCH_PID:-}" ]]; then
    kill "$WATCH_PID" >/dev/null 2>&1 || true
    wait "$WATCH_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$STATE_DIR"
}

trap cleanup EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_CURRENT_TASK_HEARTBEAT_INTERVAL=1
export TASKLIGHT_CURRENT_TASK_ACTIVE_LEASE_SECONDS=10
export CODEX_THREAD_ID="$THREAD_ID"
export CODEX_HOME="$STATE_DIR/fake-codex-home"
export CODEX_PRIVATE_ACTIVE_WINDOW_SECONDS=30

mkdir -p "$CODEX_HOME"
python3 - "$CODEX_HOME" "$THREAD_ID" <<'PY'
import json
import sqlite3
import sys
import time
from pathlib import Path

home = Path(sys.argv[1])
thread_id = sys.argv[2]
db_path = home / "logs_2.sqlite"
con = sqlite3.connect(db_path)
con.execute("create table logs (id integer primary key autoincrement, ts integer not null, ts_nanos integer not null, level text not null, target text not null, feedback_log_body text, module_path text, file text, line integer, thread_id text, process_uuid text, estimated_bytes integer not null default 0)")
con.execute("insert into logs (ts, ts_nanos, level, target, thread_id) values (?, 0, 'INFO', 'smoke', ?)", (int(time.time()), thread_id))
con.commit()
con.close()
PY

start_json="$("$SCRIPT_PATH" start --title "smoke current codex thread" --phase smoke --progress 0.2)"
task_id="$(printf '%s\n' "$start_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["task"]["task_id"])')"
binding_path="$STATE_DIR/thread_bindings/$THREAD_ID.json"

test -s "$binding_path"

python3 - "$binding_path" "$task_id" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
task_id = sys.argv[2]
payload = json.loads(path.read_text(encoding="utf-8"))
assert payload["thread_id"], payload
assert payload["task_id"] == task_id, payload
assert payload["status"] == "active", payload
assert payload["watch_pid"], payload
PY

WATCH_PID="$(python3 - "$binding_path" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(payload["watch_pid"])
PY
)"

sleep 2.2

"$SCRIPT_PATH" heartbeat --phase smoke --progress 0.4 >/dev/null

python3 - "$STATE_DIR/tasks/$task_id.json" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["status"] == "running", payload
assert payload["progress"] == 0.4, payload
PY

"$SCRIPT_PATH" done --summary "smoke done" >/dev/null
"$SCRIPT_PATH" verify >/dev/null

python3 - "$binding_path" "$STATE_DIR/tasks/$task_id.json" <<'PY'
import json
import sys
from pathlib import Path

binding = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
task = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
assert binding["status"] == "released", binding
assert binding["released_at"], binding
assert task["status"] == "done_verified", task
PY

export TASKLIGHT_CURRENT_TASK_ACTIVE_LEASE_SECONDS=2
python3 - "$CODEX_HOME" "$THREAD_ID" <<'PY'
import sqlite3
import sys
import time
from pathlib import Path

home = Path(sys.argv[1])
thread_id = sys.argv[2]
db_path = home / "logs_2.sqlite"
con = sqlite3.connect(db_path)
con.execute("delete from logs where thread_id = ?", (thread_id,))
con.execute("insert into logs (ts, ts_nanos, level, target, thread_id) values (?, 0, 'INFO', 'smoke', ?)", (int(time.time()) - 120, thread_id))
con.commit()
con.close()
PY
idle_json="$("$SCRIPT_PATH" start --title "smoke current codex idle release" --phase smoke_idle --progress 0.3)"
idle_task_id="$(printf '%s\n' "$idle_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["task"]["task_id"])')"
WATCH_PID="$(python3 - "$binding_path" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(payload["watch_pid"])
PY
)"

sleep 4

python3 - "$binding_path" "$STATE_DIR/tasks/$idle_task_id.json" <<'PY'
import json
import sys
from pathlib import Path

binding = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
task = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
assert binding["status"] == "released", binding
assert binding["released_at"], binding
assert task["status"] == "cancelled", task
PY

if env -u CODEX_THREAD_ID TASKLIGHT_STATE_DIR="$STATE_DIR" "$SCRIPT_PATH" show >/dev/null 2>&1; then
  echo "expected missing CODEX_THREAD_ID to fail closed" >&2
  exit 1
fi

echo "smoke_current_thread_binding: ok"
