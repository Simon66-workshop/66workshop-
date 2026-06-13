#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/mac/66TaskLight"

python3 -m unittest discover -s "$ROOT_DIR/cli/tests" -p 'test_*.py'
(cd "$PACKAGE_DIR" && swift build)
(cd "$PACKAGE_DIR" && swift run TaskLightChecks)
"$ROOT_DIR/script/smoke_ui_refresh_latency.sh"
"$ROOT_DIR/script/smoke_signal_bus.sh"
"$ROOT_DIR/script/smoke_state_projector.sh"
"$ROOT_DIR/script/smoke_turn_runtime_arbiter.sh"
"$ROOT_DIR/script/smoke_multitask.sh"
"$ROOT_DIR/script/smoke_verify_gate.sh"
"$ROOT_DIR/script/smoke_ttl.sh"
"$ROOT_DIR/script/smoke_invalid_task_json.sh"
"$ROOT_DIR/script/smoke_observations.sh"
"$ROOT_DIR/script/smoke_current_thread_binding.sh"
"$ROOT_DIR/script/smoke_appserver_bridge.sh"
"$ROOT_DIR/script/smoke_appserver_thread_watcher.sh"
"$ROOT_DIR/script/smoke_codex_thread_coverage.sh"
"$ROOT_DIR/script/smoke_status_reflection_cases.sh"
"$ROOT_DIR/script/smoke_workspace_coverage.sh"
"$ROOT_DIR/script/smoke_hooks_config.sh"
"$ROOT_DIR/script/smoke_hook_signal_bridge.sh"
"$ROOT_DIR/script/smoke_stop_priority_guard.sh"
"$ROOT_DIR/script/smoke_hook_bridge_launch_agent.sh"
"$ROOT_DIR/script/smoke_signal_fusion.sh"
"$ROOT_DIR/script/smoke_private_probe_confidence.sh"
"$ROOT_DIR/script/smoke_current_thread_turn_identity.sh"
"$ROOT_DIR/script/smoke_observer_health.sh"
"$ROOT_DIR/script/smoke_self_review.sh"
"$ROOT_DIR/script/smoke_self_review_scope.sh"
python3 "$ROOT_DIR/script/state_projector.py" --once >/dev/null
"$ROOT_DIR/script/check_state_projector.sh" >/dev/null
"$ROOT_DIR/script/build_and_run.sh" --verify
"$ROOT_DIR/script/check_ui_client.sh" >/dev/null
