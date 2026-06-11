#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKLIGHT_BIN="$ROOT_DIR/tasklight"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
THREAD_ID="${CODEX_THREAD_ID:-}"
THREAD_BINDINGS_DIR="${TASKLIGHT_THREAD_BINDINGS_DIR:-$STATE_DIR/thread_bindings}"
HEARTBEAT_INTERVAL="${TASKLIGHT_CURRENT_TASK_HEARTBEAT_INTERVAL:-20}"
ACTIVE_LEASE_SECONDS="${TASKLIGHT_CURRENT_TASK_ACTIVE_LEASE_SECONDS:-180}"
DEFAULT_PHASE="${TASKLIGHT_CURRENT_TASK_PHASE:-codex_session}"
DEFAULT_PROGRESS="${TASKLIGHT_CURRENT_TASK_PROGRESS:-0.12}"

require_thread_id() {
  if [[ -z "$THREAD_ID" ]]; then
    echo "CODEX_THREAD_ID is required for current-session managed binding" >&2
    exit 2
  fi
}

ensure_layout() {
  mkdir -p "$THREAD_BINDINGS_DIR"
}

binding_path() {
  printf '%s\n' "$THREAD_BINDINGS_DIR/$THREAD_ID.json"
}

binding_exists() {
  [[ -s "$(binding_path)" ]]
}

binding_json() {
  python3 - "$(binding_path)" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    print("{}")
    raise SystemExit(0)
payload = json.loads(path.read_text(encoding="utf-8"))
print(json.dumps(payload, ensure_ascii=True))
PY
}

binding_field() {
  local field="$1"
  python3 - "$(binding_path)" "$field" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
field = sys.argv[2]
if not path.exists():
    raise SystemExit(1)
payload = json.loads(path.read_text(encoding="utf-8"))
value = payload.get(field)
if value is None:
    raise SystemExit(1)
print(value)
PY
}

write_binding() {
  local task_id="$1"
  local title="$2"
  local phase="$3"
  local progress="$4"
  local status="$5"
  local watch_pid="${6:-}"
  local released_at="${7:-}"
  local now cwd path
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  cwd="$PWD"
  path="$(binding_path)"
  python3 - "$path" "$THREAD_ID" "$task_id" "$title" "$cwd" "$now" "$phase" "$progress" "$status" "$watch_pid" "$released_at" <<'PY'
import json
import os
import tempfile
from pathlib import Path
import sys

path = Path(sys.argv[1])
thread_id, task_id, title, cwd, now, phase, progress, status, watch_pid, released_at = sys.argv[2:12]
payload = {}
if path.exists():
    payload = json.loads(path.read_text(encoding="utf-8"))
payload.update(
    {
        "thread_id": thread_id,
        "task_id": task_id,
        "title": title,
        "cwd": cwd,
        "created_at": payload.get("created_at") or now,
        "updated_at": now,
        "phase": phase,
        "progress": float(progress),
        "status": status,
        "watch_pid": int(watch_pid) if watch_pid else None,
        "released_at": released_at or None,
    }
)
path.parent.mkdir(parents=True, exist_ok=True)
fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
with os.fdopen(fd, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=True, sort_keys=True, indent=2)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
os.replace(tmp_name, path)
dir_fd = os.open(path.parent, os.O_DIRECTORY)
try:
    os.fsync(dir_fd)
finally:
    os.close(dir_fd)
PY
}

stop_watch_pid() {
  local pid="${1:-}"
  if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
  fi
}

current_task_status() {
  local task_id="$1"
  "$TASKLIGHT_BIN" show "$task_id" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status","missing"))'
}

is_nonterminal_status() {
  case "$1" in
    blocked|done_verified|cancelled|stale|invalid_json|missing)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

start_watcher() {
  local watch_path tasklight_bin interval active_lease_seconds
  watch_path="$(binding_path)"
  tasklight_bin="$TASKLIGHT_BIN"
  interval="$HEARTBEAT_INTERVAL"
  active_lease_seconds="$ACTIVE_LEASE_SECONDS"
  nohup python3 - "$watch_path" "$tasklight_bin" "$interval" "$active_lease_seconds" >/dev/null 2>&1 <<'PY' &
import json
import os
import subprocess
import sys
import time
import tempfile
from datetime import datetime, timezone
from pathlib import Path

path = Path(sys.argv[1])
tasklight_bin = sys.argv[2]
interval = float(sys.argv[3])
active_lease_seconds = float(sys.argv[4])

def parse_ts(value):
    if not value:
        return None
    normalized = str(value).replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(normalized)
    except ValueError:
        return None

def now_string():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

def write_payload(payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=True, sort_keys=True, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp_name, path)
    dir_fd = os.open(path.parent, os.O_DIRECTORY)
    try:
        os.fsync(dir_fd)
    finally:
        os.close(dir_fd)

def release_idle_binding(payload):
    task_id = payload.get("task_id")
    if task_id:
        subprocess.run(
            [tasklight_bin, "clear", "--task-id", str(task_id)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    now = now_string()
    payload["status"] = "released"
    payload["released_at"] = now
    payload["updated_at"] = now
    payload["watch_pid"] = None
    write_payload(payload)

while True:
    time.sleep(interval)
    if not path.exists():
        raise SystemExit(0)
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("status") != "active":
        raise SystemExit(0)
    updated_at = parse_ts(payload.get("updated_at"))
    if updated_at is None:
        release_idle_binding(payload)
        raise SystemExit(0)
    idle_seconds = datetime.now(timezone.utc).timestamp() - updated_at.timestamp()
    if idle_seconds > active_lease_seconds:
        release_idle_binding(payload)
        raise SystemExit(0)
    task_id = payload.get("task_id")
    phase = payload.get("phase") or "codex_session"
    progress = payload.get("progress")
    if progress is None:
        progress = 0.12
    subprocess.run(
        [tasklight_bin, "heartbeat", "--task-id", str(task_id), "--phase", str(phase), "--progress", str(progress)],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
PY
  printf '%s\n' "$!"
}

resolve_binding_task() {
  if ! binding_exists; then
    return 1
  fi
  binding_field task_id
}

resolve_binding_title() {
  if ! binding_exists; then
    return 1
  fi
  binding_field title
}

release_binding() {
  local task_id="$1"
  local title="$2"
  local phase="$3"
  local progress="$4"
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  write_binding "$task_id" "$title" "$phase" "$progress" "released" "" "$now"
}

show_binding() {
  local task_id binding task
  binding="$(binding_json)"
  if task_id="$(resolve_binding_task 2>/dev/null)"; then
    task="$("$TASKLIGHT_BIN" show "$task_id" 2>/dev/null || printf '%s\n' "null")"
  else
    task="null"
  fi
  python3 - "$binding" "$task" <<'PY'
import json
import sys

binding = json.loads(sys.argv[1])
task = json.loads(sys.argv[2]) if sys.argv[2] != "null" else None
print(json.dumps({"binding": binding, "task": task}, ensure_ascii=True, sort_keys=True, indent=2))
PY
}

require_thread_id
ensure_layout

command="${1:-}"
if [[ -z "$command" ]]; then
  echo "usage: $0 {start|heartbeat|done|verify|block|clear|show}" >&2
  exit 2
fi
shift

case "$command" in
  start)
    title=""
    phase="$DEFAULT_PHASE"
    progress="$DEFAULT_PROGRESS"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --title)
          title="$2"
          shift 2
          ;;
        --phase)
          phase="$2"
          shift 2
          ;;
        --progress)
          progress="$2"
          shift 2
          ;;
        *)
          echo "unknown argument: $1" >&2
          exit 2
          ;;
      esac
    done
    if [[ -z "$title" ]]; then
      echo "--title is required" >&2
      exit 2
    fi

    task_id=""
    if existing_task_id="$(resolve_binding_task 2>/dev/null)"; then
      existing_status="$(current_task_status "$existing_task_id" || printf '%s\n' "missing")"
      if is_nonterminal_status "$existing_status"; then
        task_id="$existing_task_id"
      fi
      if existing_watch_pid="$(binding_field watch_pid 2>/dev/null || true)"; then
        stop_watch_pid "$existing_watch_pid"
      fi
    fi

    if [[ -z "$task_id" ]]; then
      start_json="$("$TASKLIGHT_BIN" start --title "$title")"
      task_id="$(printf '%s\n' "$start_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["task_id"])')"
    fi

    "$TASKLIGHT_BIN" heartbeat --task-id "$task_id" --phase "$phase" --progress "$progress" >/dev/null
    watch_pid="$(start_watcher)"
    write_binding "$task_id" "$title" "$phase" "$progress" "active" "$watch_pid"
    show_binding
    ;;
  heartbeat)
    phase=""
    progress=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --phase)
          phase="$2"
          shift 2
          ;;
        --progress)
          progress="$2"
          shift 2
          ;;
        *)
          echo "unknown argument: $1" >&2
          exit 2
          ;;
      esac
    done
    if [[ -z "$phase" || -z "$progress" ]]; then
      echo "--phase and --progress are required" >&2
      exit 2
    fi
    task_id="$(resolve_binding_task)"
    title="$(resolve_binding_title 2>/dev/null || printf '%s\n' "$task_id")"
    "$TASKLIGHT_BIN" heartbeat --task-id "$task_id" --phase "$phase" --progress "$progress" >/dev/null
    watch_pid="$(binding_field watch_pid 2>/dev/null || true)"
    write_binding "$task_id" "$title" "$phase" "$progress" "active" "$watch_pid"
    show_binding
    ;;
  done)
    summary=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --summary)
          summary="$2"
          shift 2
          ;;
        *)
          echo "unknown argument: $1" >&2
          exit 2
          ;;
      esac
    done
    if [[ -z "$summary" ]]; then
      echo "--summary is required" >&2
      exit 2
    fi
    task_id="$(resolve_binding_task)"
    title="$(resolve_binding_title 2>/dev/null || printf '%s\n' "$task_id")"
    phase="$(binding_field phase 2>/dev/null || printf '%s\n' "$DEFAULT_PHASE")"
    progress="$(binding_field progress 2>/dev/null || printf '%s\n' "$DEFAULT_PROGRESS")"
    stop_watch_pid "$(binding_field watch_pid 2>/dev/null || true)"
    "$TASKLIGHT_BIN" done --task-id "$task_id" --summary "$summary" >/dev/null
    release_binding "$task_id" "$title" "$phase" "$progress"
    show_binding
    ;;
  verify)
    task_id="$(resolve_binding_task)"
    title="$(resolve_binding_title 2>/dev/null || printf '%s\n' "$task_id")"
    phase="$(binding_field phase 2>/dev/null || printf '%s\n' "$DEFAULT_PHASE")"
    progress="$(binding_field progress 2>/dev/null || printf '%s\n' "$DEFAULT_PROGRESS")"
    stop_watch_pid "$(binding_field watch_pid 2>/dev/null || true)"
    "$TASKLIGHT_BIN" verify --task-id "$task_id" >/dev/null
    release_binding "$task_id" "$title" "$phase" "$progress"
    show_binding
    ;;
  block)
    reason=""
    message=""
    evidence=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --reason)
          reason="$2"
          shift 2
          ;;
        --message)
          message="$2"
          shift 2
          ;;
        --evidence)
          evidence="$2"
          shift 2
          ;;
        *)
          echo "unknown argument: $1" >&2
          exit 2
          ;;
      esac
    done
    if [[ -z "$reason" || -z "$message" || -z "$evidence" ]]; then
      echo "--reason --message --evidence are required" >&2
      exit 2
    fi
    task_id="$(resolve_binding_task)"
    title="$(resolve_binding_title 2>/dev/null || printf '%s\n' "$task_id")"
    phase="$(binding_field phase 2>/dev/null || printf '%s\n' "$DEFAULT_PHASE")"
    progress="$(binding_field progress 2>/dev/null || printf '%s\n' "$DEFAULT_PROGRESS")"
    stop_watch_pid "$(binding_field watch_pid 2>/dev/null || true)"
    "$TASKLIGHT_BIN" block --task-id "$task_id" --reason "$reason" --message "$message" --evidence "$evidence" >/dev/null
    release_binding "$task_id" "$title" "$phase" "$progress"
    show_binding
    ;;
  clear)
    task_id="$(resolve_binding_task)"
    title="$(resolve_binding_title 2>/dev/null || printf '%s\n' "$task_id")"
    phase="$(binding_field phase 2>/dev/null || printf '%s\n' "$DEFAULT_PHASE")"
    progress="$(binding_field progress 2>/dev/null || printf '%s\n' "$DEFAULT_PROGRESS")"
    stop_watch_pid "$(binding_field watch_pid 2>/dev/null || true)"
    "$TASKLIGHT_BIN" clear --task-id "$task_id" >/dev/null
    release_binding "$task_id" "$title" "$phase" "$progress"
    show_binding
    ;;
  show)
    show_binding
    ;;
  *)
    echo "unknown command: $command" >&2
    exit 2
    ;;
esac
