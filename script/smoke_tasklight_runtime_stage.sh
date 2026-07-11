#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-runtime-stage-XXXXXX")"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

RUNTIME_ROOT="$(TASKLIGHT_STATE_DIR="$STATE_DIR" "$ROOT_DIR/script/stage_tasklight_runtime.sh")"
cmp -s "$ROOT_DIR/script/state_projector.py" "$RUNTIME_ROOT/script/state_projector.py"
cmp -s "$ROOT_DIR/script/codex_quota_appserver_watcher.py" "$RUNTIME_ROOT/script/codex_quota_appserver_watcher.py"
cmp -s "$ROOT_DIR/design/state-projector/params/runtime_confidence.json" "$RUNTIME_ROOT/design/state-projector/params/runtime_confidence.json"

echo "smoke_tasklight_runtime_stage: ok"
