#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/mac/66TaskLight"

python3 -m unittest discover -s "$ROOT_DIR/cli/tests" -p 'test_*.py'
(cd "$PACKAGE_DIR" && swift build)
(cd "$PACKAGE_DIR" && swift run TaskLightChecks)
"$ROOT_DIR/script/smoke_multitask.sh"
"$ROOT_DIR/script/smoke_verify_gate.sh"
"$ROOT_DIR/script/smoke_ttl.sh"
"$ROOT_DIR/script/smoke_invalid_task_json.sh"
"$ROOT_DIR/script/smoke_observations.sh"
"$ROOT_DIR/script/smoke_current_thread_binding.sh"
"$ROOT_DIR/script/smoke_observer_health.sh"
"$ROOT_DIR/script/build_and_run.sh" --verify
