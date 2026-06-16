# Scope Candidate P0-check-all-total-fix

- Task ID: `P0-check-all-total-fix`
- Task Types: `release_audit, tooling`
- Generated At: `2026-06-15T06:22:10Z`
- Recommended Decision: `NEEDS_HUMAN_REVIEW`

## Recommended Include Paths
- `README.md`
- `config/self-review/`
- `docs/`
- `script/check_all.sh`
- `script/self-review/`
- `script/smoke_self_review.sh`
- `script/smoke_self_review_generate_scope.sh`
- `script/smoke_self_review_scope.sh`

## Recommended Exclude Paths
- none

## In-Scope Candidate Files
- `docs/CODEX_WORKSPACE_ONBOARDING.md`
- `docs/reports`
- `script/check_all.sh`

## Out-of-Scope Dirty Files
- `.codex`
- `cli/tasklight.py`
- `cli/tests/test_tasklight.py`
- `mac/66TaskLight/Sources/TaskLightApp/Components/LuckyCatCompactShell.swift`
- `mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift`
- `mac/66TaskLight/Sources/TaskLightApp/Theme/LuckyCatLayout.swift`
- `mac/66TaskLight/Sources/TaskLightChecks/main.swift`
- `mac/66TaskLight/Sources/TaskLightCore/TaskLightStore.swift`
- `mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift`
- `script/codex_current_task_watcher.py`
- `script/codex_hook_event.py`
- `script/hook_signal_bridge.py`
- `script/onboard_workspace_for_monitoring.py`
- `script/onboard_workspace_for_monitoring.sh`
- `script/smoke_check_all_total_schema.sh`
- `script/smoke_current_thread_turn_identity.sh`
- `script/smoke_hook_signal_bridge.sh`
- `script/smoke_hooks_config.sh`
- `script/smoke_state_projector.sh`
- `script/smoke_stop_priority_guard.sh`
- `script/smoke_workspace_onboarding.sh`
- `script/state_projector.py`
- `script/tasklight_signal_bus.py`

## Risk Classification
- `risky_launch_trust`: `9`
- `risky_auth_secret`: `0`
- `build_artifacts`: `0`
- `cache_artifacts`: `0`
- `docs_assets`: `0`
- `app_assets`: `0`
- `unknown`: `16`

## Why Risky Files Were Classified
- `docs/CODEX_WORKSPACE_ONBOARDING.md`: launch/trust match: trust, workspace coverage
- `mac/66TaskLight/Sources/TaskLightApp/Components/LuckyCatCompactShell.swift`: launch/trust match: workspace coverage
- `mac/66TaskLight/Sources/TaskLightChecks/main.swift`: launch/trust match: trust, workspace coverage
- `mac/66TaskLight/Sources/TaskLightCore/TaskLightStore.swift`: launch/trust match: trust
- `mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift`: launch/trust match: trust
- `script/check_all.sh`: launch/trust match: launch_agent
- `script/hook_signal_bridge.py`: launch/trust match: trust
- `script/onboard_workspace_for_monitoring.py`: launch/trust match: trust
- `script/smoke_hooks_config.sh`: launch/trust match: trust

## Suggested Command
```bash
python3 script/self-review/run_self_review.py --task-id P0-check-all-total-fix --task-type release_audit --task-type tooling --scope-file /Users/macmini-simon66/Documents/Codex状态桌面栏提醒/docs/reports/self-review/P0-check-all-total-fix/self-review-scope.json --evidence-profile full --mode final
```

## Human Review Warning
- Launch/trust or auth/secret risk exists. Do not auto-apply this scope without review.
