#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKLIGHT_BIN="$ROOT_DIR/tasklight"
WATCHER_SCRIPT="$ROOT_DIR/script/codex_current_task_watcher.py"
PRIVATE_PROBE_SCRIPT="$ROOT_DIR/script/codex_private_state_probe.py"
FUSION_SCRIPT="$ROOT_DIR/script/codex_signal_fusion.py"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
THREAD_ID="${CODEX_THREAD_ID:-}"
THREAD_BINDINGS_DIR="${TASKLIGHT_THREAD_BINDINGS_DIR:-$STATE_DIR/thread_bindings}"
HEARTBEAT_INTERVAL="${TASKLIGHT_CURRENT_TASK_HEARTBEAT_INTERVAL:-10}"
ACTIVE_LEASE_SECONDS="${TASKLIGHT_CURRENT_TASK_ACTIVE_LEASE_SECONDS:-45}"
DEFAULT_PHASE="${TASKLIGHT_CURRENT_TASK_PHASE:-codex_session}"
DEFAULT_PROGRESS="${TASKLIGHT_CURRENT_TASK_PROGRESS:-0.12}"
STARTED_WATCH_PID=""
BINDING_TURN_ID=""
BINDING_EPOCH=""
BINDING_TASK_IDENTITY=""

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
        "turn_id": os.environ.get("TASKLIGHT_BINDING_TURN_ID") or payload.get("turn_id"),
        "binding_epoch": int(os.environ.get("TASKLIGHT_BINDING_EPOCH") or payload.get("binding_epoch") or 1),
        "task_identity": os.environ.get("TASKLIGHT_BINDING_TASK_IDENTITY") or payload.get("task_identity"),
        "quiet_count": int(os.environ.get("TASKLIGHT_BINDING_QUIET_COUNT") or payload.get("quiet_count") or 0),
        "last_fusion_decision": payload.get("last_fusion_decision"),
        "last_signal_confidence": payload.get("last_signal_confidence"),
        "last_signal_source": payload.get("last_signal_source"),
        "last_source_quality": payload.get("last_source_quality"),
        "last_inferred_status": payload.get("last_inferred_status"),
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

watch_pid_is_alive() {
  local pid="${1:-}"
  [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1
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
  STARTED_WATCH_PID="$(python3 - "$WATCHER_SCRIPT" "$watch_path" "$tasklight_bin" "$interval" "$active_lease_seconds" <<'PY'
import os
import subprocess
import sys

watcher_script, watch_path, tasklight_bin, interval, active_lease_seconds = sys.argv[1:6]
devnull = open(os.devnull, "wb")
process = subprocess.Popen(
    [
        "python3",
        watcher_script,
        watch_path,
        tasklight_bin,
        interval,
        active_lease_seconds,
        os.environ.get("CODEX_THREAD_ID", ""),
        os.environ.get("TASKLIGHT_PRIVATE_PROBE_SCRIPT", ""),
        os.environ.get("TASKLIGHT_FUSION_SCRIPT", ""),
    ],
    stdin=subprocess.DEVNULL,
    stdout=devnull,
    stderr=devnull,
    close_fds=True,
    start_new_session=True,
)
print(process.pid)
PY
)"
}

detect_turn_id() {
  python3 "$PRIVATE_PROBE_SCRIPT" --thread-id "$THREAD_ID" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("turn_id") or "")' 2>/dev/null || true
}

prepare_binding_identity() {
  local new_turn_id existing_epoch next_epoch
  new_turn_id="$(detect_turn_id)"
  existing_epoch="$(binding_field binding_epoch 2>/dev/null || printf '%s\n' "0")"
  next_epoch="$((existing_epoch + 1))"
  BINDING_TURN_ID="$new_turn_id"
  if [[ -n "$new_turn_id" ]]; then
    BINDING_EPOCH="${existing_epoch:-1}"
    if [[ "$BINDING_EPOCH" == "0" ]]; then
      BINDING_EPOCH="1"
    fi
    BINDING_TASK_IDENTITY="$THREAD_ID:$new_turn_id"
  else
    BINDING_EPOCH="$next_epoch"
    BINDING_TASK_IDENTITY="$THREAD_ID:epoch-$BINDING_EPOCH"
  fi
  export TASKLIGHT_BINDING_TURN_ID="$BINDING_TURN_ID"
  export TASKLIGHT_BINDING_EPOCH="$BINDING_EPOCH"
  export TASKLIGHT_BINDING_TASK_IDENTITY="$BINDING_TASK_IDENTITY"
  export TASKLIGHT_BINDING_QUIET_COUNT="0"
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
export TASKLIGHT_PRIVATE_PROBE_SCRIPT="$PRIVATE_PROBE_SCRIPT"
export TASKLIGHT_FUSION_SCRIPT="$FUSION_SCRIPT"

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
    prepare_binding_identity
    if existing_task_id="$(resolve_binding_task 2>/dev/null)"; then
      existing_status="$(current_task_status "$existing_task_id" || printf '%s\n' "missing")"
      existing_identity="$(binding_field task_identity 2>/dev/null || true)"
      if [[ -z "$BINDING_TURN_ID" && -n "$existing_identity" ]] && is_nonterminal_status "$existing_status"; then
        BINDING_EPOCH="$(binding_field binding_epoch 2>/dev/null || printf '%s\n' "$BINDING_EPOCH")"
        BINDING_TASK_IDENTITY="$existing_identity"
        export TASKLIGHT_BINDING_EPOCH="$BINDING_EPOCH"
        export TASKLIGHT_BINDING_TASK_IDENTITY="$BINDING_TASK_IDENTITY"
      fi
      if is_nonterminal_status "$existing_status" && [[ "$existing_identity" == "$BINDING_TASK_IDENTITY" ]]; then
        task_id="$existing_task_id"
      elif is_nonterminal_status "$existing_status"; then
        "$TASKLIGHT_BIN" release --task-id "$existing_task_id" >/dev/null 2>&1 || true
      elif [[ "$existing_status" == "stale" ]]; then
        "$TASKLIGHT_BIN" release --task-id "$existing_task_id" >/dev/null 2>&1 || true
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
    start_watcher
    watch_pid="$STARTED_WATCH_PID"
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
    export TASKLIGHT_BINDING_QUIET_COUNT="0"
    "$TASKLIGHT_BIN" heartbeat --task-id "$task_id" --phase "$phase" --progress "$progress" >/dev/null
    watch_pid="$(binding_field watch_pid 2>/dev/null || true)"
    if ! watch_pid_is_alive "$watch_pid"; then
      start_watcher
      watch_pid="$STARTED_WATCH_PID"
    fi
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
