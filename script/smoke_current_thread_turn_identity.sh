#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/script/codex_current_task.sh"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-turn-identity-XXXXXX")"
CODEX_HOME_DIR="$STATE_DIR/fake-codex"
THREAD_ID="thread-turn-identity"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_CURRENT_TASK_HEARTBEAT_INTERVAL=1
export TASKLIGHT_CURRENT_TASK_ACTIVE_LEASE_SECONDS=10
export TASKLIGHT_APPSERVER_DISABLED=1
export CODEX_THREAD_ID="$THREAD_ID"
export CODEX_HOME="$CODEX_HOME_DIR"

write_private_state() {
  local turn_id="$1"
  local age="$2"
  mkdir -p "$CODEX_HOME_DIR/process_manager"
  python3 - "$CODEX_HOME_DIR" "$THREAD_ID" "$turn_id" "$age" <<'PY'
import json
import sqlite3
import sys
import time
from pathlib import Path

home = Path(sys.argv[1])
thread_id = sys.argv[2]
turn_id = sys.argv[3]
age = int(sys.argv[4])
home.mkdir(parents=True, exist_ok=True)
con = sqlite3.connect(home / "logs_2.sqlite")
con.execute("drop table if exists logs")
con.execute("create table logs (id integer primary key autoincrement, ts integer not null, ts_nanos integer not null, level text not null, target text not null, feedback_log_body text, module_path text, file text, line integer, thread_id text, process_uuid text, estimated_bytes integer not null default 0)")
con.execute("insert into logs (ts, ts_nanos, level, target, thread_id) values (?, 0, 'INFO', 'smoke', ?)", (int(time.time()) - age, thread_id))
con.commit()
con.close()
(home / "process_manager" / "chat_processes.json").write_text(json.dumps([
    {
        "conversationId": thread_id,
        "turnId": turn_id,
        "itemId": "item-" + turn_id,
        "osPid": None,
        "updatedAtMs": int((time.time() - age) * 1000),
        "startedAtMs": int((time.time() - age) * 1000),
        "command": "smoke",
        "cwd": str(home)
    }
]), encoding="utf-8")
PY
}

task_from_json() {
  python3 -c 'import json,sys; print(json.load(sys.stdin)["task"]["task_id"])'
}

identity_from_binding() {
  local binding_path="$STATE_DIR/thread_bindings/$THREAD_ID.json"
  python3 - "$binding_path" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(payload.get("task_identity"))
PY
}

write_private_state "turn-1" 0
first_json="$("$SCRIPT_PATH" start --title "turn one" --phase smoke --progress 0.2)"
first_task="$(printf '%s\n' "$first_json" | task_from_json)"
first_identity="$(identity_from_binding)"
"$SCRIPT_PATH" done --summary "turn one done" >/dev/null
"$SCRIPT_PATH" verify >/dev/null

write_private_state "turn-2" 0
second_json="$("$SCRIPT_PATH" start --title "turn two" --phase smoke --progress 0.3)"
second_task="$(printf '%s\n' "$second_json" | task_from_json)"
second_identity="$(identity_from_binding)"

if [[ "$first_task" == "$second_task" || "$first_identity" == "$second_identity" ]]; then
  echo "expected new turn to bind a new task identity" >&2
  exit 1
fi

python3 - "$STATE_DIR/tasks/$first_task.json" "$STATE_DIR/tasks/$second_task.json" <<'PY'
import json
import sys
from pathlib import Path
first = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
second = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
assert first["status"] == "done_verified", first
assert second["status"] == "running", second
PY

write_private_state "turn-2" 120
sleep 4

python3 - "$STATE_DIR/thread_bindings/$THREAD_ID.json" "$STATE_DIR/tasks/$second_task.json" <<'PY'
import json
import sys
from pathlib import Path
binding = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
task = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
assert binding["status"] == "released", binding
assert binding["quiet_count"] >= 3, binding
assert task["status"] == "cancelled", task
assert task["phase"] == "released", task
PY

echo "smoke_current_thread_turn_identity: ok"
