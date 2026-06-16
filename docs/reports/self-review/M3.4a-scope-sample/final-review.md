# Self-Review M3.4a-scope-sample

- decision: `NEEDS_HUMAN_REVIEW`
- total_score: `100.0`
- task_types: `state_projector, hook_bridge`
- hard_gate_failed: `False`
- review_scope: `scoped`
- included_paths: `README.md, config/self-review, docs/self-review, script/self-review, script/smoke_self_review.sh, script/smoke_self_review_scope.sh`
- excluded_paths: `__pycache__, dist, mac/66TaskLight/.build`
- out_of_scope_dirty_files: `.codex, config, docs/CODEX_THREAD_COVERAGE.md, docs/CODEX_WORKSPACE_ONBOARDING.md, docs/STATUS_REFLECTION_LOOP.md, docs/reports, mac/66TaskLight/Sources/TaskLightApp/Components/LuckyCatCompactShell.swift, mac/66TaskLight/Sources/TaskLightApp/Screens/LuckyCatCompactView.swift, mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift, mac/66TaskLight/Sources/TaskLightChecks/main.swift, mac/66TaskLight/Sources/TaskLightCore/TaskLightStore.swift, mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift, script/appserver_thread_watcher.py, script/capture_status_mismatch.sh, script/check_all.sh, script/check_codex_hooks_trust.py, script/check_codex_thread_coverage.py, script/check_codex_thread_coverage.sh, script/check_codex_workspaces_coverage.py, script/check_codex_workspaces_coverage.sh, script/check_state_projector.sh, script/discover_codex_workspaces.py, script/install_hooks_for_workspace.sh, script/install_hooks_for_workspaces.sh, script/smoke_appserver_bridge.sh, script/smoke_codex_thread_coverage.sh, script/smoke_hooks_config.sh, script/smoke_status_reflection_cases.sh, script/smoke_workspace_coverage.sh, script/state_projector.py, script/status_reflection_case.py, script/tasklight_signal_bus.py`
- scope_decision: `NEEDS_HUMAN_REVIEW`

## State Accuracy Matrix
- `appserver_active_like_running`: `pass` via `smoke_turn_runtime_arbiter`
- `appserver_unknown_not_running`: `pass` via `smoke_turn_runtime_arbiter`
- `hook_running_is_running`: `pass` via `smoke_turn_runtime_arbiter, smoke_state_projector`
- `multiple_projector_detected`: `pass` via `check_state_projector, smoke_turn_runtime_arbiter`
- `old_projector_writer_detected`: `pass` via `check_state_projector, smoke_turn_runtime_arbiter`
- `permission_request_blocked`: `pass` via `smoke_turn_runtime_arbiter`
- `private_global_only_not_running`: `pass` via `smoke_turn_runtime_arbiter`
- `process_only_not_running`: `pass` via `smoke_turn_runtime_arbiter`
- `stop_is_pending`: `pass` via `smoke_turn_runtime_arbiter, smoke_state_projector`
- `verify_is_done`: `pass` via `smoke_turn_runtime_arbiter, smoke_state_projector`

## Reflection
- `unrelated_dirty_worktree`: `CONDITIONAL_PASS` root=`working tree contains unrelated dirty files outside the active review scope`
- `launch_agent_unhealthy`: `NEEDS_HUMAN_REVIEW` root=`launch or trust changes exist outside the active review scope`

## Next Step
- `keep using a scope file or clean unrelated worktree drift before final acceptance`
- `route this task through human review even if in-scope evidence is clean`
