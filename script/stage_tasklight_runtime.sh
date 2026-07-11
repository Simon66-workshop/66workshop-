#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"

if [[ "${1:-}" == "--state-dir" ]]; then
  STATE_DIR="$2"
fi

RUNTIME_ROOT="${TASKLIGHT_RUNTIME_ROOT:-$STATE_DIR/runtime/tasklight-python}"
mkdir -p "$RUNTIME_ROOT/script" "$RUNTIME_ROOT/design/state-projector/params"
cp "$ROOT_DIR"/script/*.py "$RUNTIME_ROOT/script/"
cp "$ROOT_DIR"/design/state-projector/params/*.json "$RUNTIME_ROOT/design/state-projector/params/"

printf '%s\n' "$RUNTIME_ROOT"
