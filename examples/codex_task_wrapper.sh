#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--" ]]; then
  shift
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKLIGHT_SCRIPT="$ROOT_DIR/tasklight"
TASK_TITLE="${TASK_TITLE:-Codex workflow task}"
TASKLIGHT_PHASE="${TASKLIGHT_PHASE:-running}"
TASKLIGHT_HEARTBEAT_INTERVAL="${TASKLIGHT_HEARTBEAT_INTERVAL:-15}"
TASKLIGHT_COMMAND_SUMMARY="${TASKLIGHT_COMMAND_SUMMARY:-workflow completed}"

if [[ $# -eq 0 ]]; then
  echo "usage: $0 -- <command>" >&2
  exit 2
fi

command=("$@")

task_start_json="$("$TASKLIGHT_SCRIPT" start --title "$TASK_TITLE" --print-id)"
task_id="$(printf '%s\n' "$task_start_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["task_id"])')"

echo "task_id=$task_id"
export TASKLIGHT_TASK_ID="$task_id"

heartbeat_running=1
heartbeat_loop() {
  while [[ "$heartbeat_running" -eq 1 ]]; do
    sleep "$TASKLIGHT_HEARTBEAT_INTERVAL"
    if [[ "$heartbeat_running" -eq 1 ]]; then
      "$TASKLIGHT_SCRIPT" heartbeat --task-id "$task_id" --phase "$TASKLIGHT_PHASE" --progress 0.15 >/dev/null || true
    fi
  done
}

heartbeat_loop &
heartbeat_pid="$!"

cleanup() {
  heartbeat_running=0
  kill "$heartbeat_pid" >/dev/null 2>&1 || true
  wait "$heartbeat_pid" >/dev/null 2>&1 || true
}

block_task() {
  local reason="$1"
  local message="$2"
  local evidence="$3"
  "$TASKLIGHT_SCRIPT" block --task-id "$task_id" --reason "$reason" --message "$message" --evidence "$evidence" >/dev/null || true
}

trap cleanup EXIT INT TERM

"$TASKLIGHT_SCRIPT" heartbeat --task-id "$task_id" --phase "start" --progress 0.05 >/dev/null || true

if "${command[@]}"; then
  if [[ -n "${TASKLIGHT_ACCEPTANCE_CMD:-}" ]]; then
    if ! bash -lc "$TASKLIGHT_ACCEPTANCE_CMD"; then
      block_task "acceptance_failed" "acceptance command failed" "TASKLIGHT_ACCEPTANCE_CMD=${TASKLIGHT_ACCEPTANCE_CMD}"
      exit 1
    fi
  fi

  if ! "$TASKLIGHT_SCRIPT" done --task-id "$task_id" --summary "$TASKLIGHT_COMMAND_SUMMARY" >/dev/null; then
    block_task "needs_human_review" "unable to write done state" "tasklight done failed"
    exit 1
  fi
  if ! "$TASKLIGHT_SCRIPT" verify --task-id "$task_id" >/dev/null; then
    block_task "needs_human_review" "unable to write verified state" "tasklight verify failed"
    exit 1
  fi
else
  rc=$?
  block_task "codex_exit_failed" "workflow command failed" "exit_code=$rc command=${command[*]}"
  exit "$rc"
fi
