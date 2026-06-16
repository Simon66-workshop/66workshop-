# Self-Review M3.5

- decision: `NEEDS_HUMAN_REVIEW`
- total_score: `90.0`
- task_types: `swift_ui, launch_agent, docs, release_audit`
- evidence_profile: `release`
- hard_gate_failed: `False`
- review_scope: `scoped`
- included_paths: `README.md, config/self-review, docs, mac/66TaskLight/Sources/TaskLightApp, mac/66TaskLight/Sources/TaskLightChecks, mac/66TaskLight/Sources/TaskLightCore, script/check_all.sh, script/check_codex_hooks_trust.py, script/check_hook_bridge_launch_agent.sh, script/install_appserver_thread_watcher_launch_agent.sh, script/install_codex_hooks_status_bridge.sh, script/install_hook_bridge_launch_agent.sh, script/install_hooks_for_workspace.sh, script/install_hooks_for_workspaces.sh, script/install_observer_launch_agent.sh, script/install_state_projector_launch_agent.sh, script/self-review, script/smoke_hook_bridge_launch_agent.sh, script/smoke_self_review.sh, script/smoke_self_review_generate_scope.sh, script/smoke_self_review_scope.sh, script/uninstall_appserver_thread_watcher_launch_agent.sh, script/uninstall_hook_bridge_launch_agent.sh, script/uninstall_observer_launch_agent.sh, script/uninstall_state_projector_launch_agent.sh`
- excluded_paths: ``
- scope_summary_path: `/Users/macmini-simon66/Documents/Codex状态桌面栏提醒/docs/reports/self-review/M3.5/scope-summary.json`
- in_scope_changed_files_count: `14`
- out_of_scope_dirty_files_count: `18`
- out_of_scope_launch_trust_count: `2`
- out_of_scope_auth_secret_count: `0`
- out_of_scope_dirty_files: `.codex, config/workspace_coverage.json, script/appserver_thread_watcher.py, script/capture_status_mismatch.sh, script/check_codex_thread_coverage.py, script/check_codex_thread_coverage.sh, script/check_codex_workspaces_coverage.py, script/check_codex_workspaces_coverage.sh, script/check_state_projector.sh, script/discover_codex_workspaces.py, script/smoke_appserver_bridge.sh, script/smoke_codex_thread_coverage.sh, script/smoke_hooks_config.sh, script/smoke_status_reflection_cases.sh, script/smoke_workspace_coverage.sh, script/state_projector.py, script/status_reflection_case.py, script/tasklight_signal_bus.py`
- scope_decision: `NEEDS_HUMAN_REVIEW`
- scope_reason: `Auto-generated scope candidate. Review manually before use.`

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
- `launch_agent_unhealthy`: `NEEDS_HUMAN_REVIEW` root=`resident process or trust surface changed`

## Next Step
- `keep using a scope file or clean unrelated worktree drift before final acceptance`
- `route this task through human review even if in-scope evidence is clean`
- `keep human review on this task even if smoke evidence passes`
