# Scope Candidate M3.5

- Task ID: `M3.5`
- Task Types: `docs, launch_agent, release_audit, swift_ui`
- Generated At: `2026-06-13T02:58:17Z`
- Recommended Decision: `NEEDS_HUMAN_REVIEW`

## Recommended Include Paths
- `README.md`
- `config/self-review/`
- `docs/`
- `mac/66TaskLight/Sources/TaskLightApp/`
- `mac/66TaskLight/Sources/TaskLightChecks/`
- `mac/66TaskLight/Sources/TaskLightCore/`
- `script/check_all.sh`
- `script/check_codex_hooks_trust.py`
- `script/check_hook_bridge_launch_agent.sh`
- `script/install_appserver_thread_watcher_launch_agent.sh`
- `script/install_codex_hooks_status_bridge.sh`
- `script/install_hook_bridge_launch_agent.sh`
- `script/install_hooks_for_workspace.sh`
- `script/install_hooks_for_workspaces.sh`
- `script/install_observer_launch_agent.sh`
- `script/install_state_projector_launch_agent.sh`
- `script/self-review/`
- `script/smoke_hook_bridge_launch_agent.sh`
- `script/smoke_self_review.sh`
- `script/smoke_self_review_generate_scope.sh`
- `script/smoke_self_review_scope.sh`
- `script/uninstall_appserver_thread_watcher_launch_agent.sh`
- `script/uninstall_hook_bridge_launch_agent.sh`
- `script/uninstall_observer_launch_agent.sh`
- `script/uninstall_state_projector_launch_agent.sh`

## Recommended Exclude Paths
- none

## In-Scope Candidate Files
- `README.md`
- `docs/CODEX_THREAD_COVERAGE.md`
- `docs/CODEX_WORKSPACE_ONBOARDING.md`
- `docs/STATUS_REFLECTION_LOOP.md`
- `docs/reports`
- `mac/66TaskLight/Sources/TaskLightApp/Components/LuckyCatCompactShell.swift`
- `mac/66TaskLight/Sources/TaskLightApp/Screens/LuckyCatCompactView.swift`
- `mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift`
- `mac/66TaskLight/Sources/TaskLightChecks/main.swift`
- `mac/66TaskLight/Sources/TaskLightCore/TaskLightStore.swift`
- `mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift`
- `script/check_codex_hooks_trust.py`
- `script/install_hooks_for_workspace.sh`
- `script/install_hooks_for_workspaces.sh`

## Out-of-Scope Dirty Files
- `.codex`
- `config/workspace_coverage.json`
- `script/appserver_thread_watcher.py`
- `script/capture_status_mismatch.sh`
- `script/check_codex_thread_coverage.py`
- `script/check_codex_thread_coverage.sh`
- `script/check_codex_workspaces_coverage.py`
- `script/check_codex_workspaces_coverage.sh`
- `script/check_state_projector.sh`
- `script/discover_codex_workspaces.py`
- `script/smoke_appserver_bridge.sh`
- `script/smoke_codex_thread_coverage.sh`
- `script/smoke_hooks_config.sh`
- `script/smoke_status_reflection_cases.sh`
- `script/smoke_workspace_coverage.sh`
- `script/state_projector.py`
- `script/status_reflection_case.py`
- `script/tasklight_signal_bus.py`

## Risk Classification
- `risky_launch_trust`: `16`
- `risky_auth_secret`: `0`
- `build_artifacts`: `0`
- `cache_artifacts`: `0`
- `docs_assets`: `0`
- `app_assets`: `0`
- `unknown`: `12`

## Why Risky Files Were Classified
- `README.md`: launch/trust match: hook install, launch_agent, trust, workspace coverage
- `config/workspace_coverage.json`: launch/trust match: path
- `docs/CODEX_THREAD_COVERAGE.md`: launch/trust match: trust
- `docs/CODEX_WORKSPACE_ONBOARDING.md`: launch/trust match: trust
- `mac/66TaskLight/Sources/TaskLightApp/Components/LuckyCatCompactShell.swift`: launch/trust match: workspace coverage
- `mac/66TaskLight/Sources/TaskLightChecks/main.swift`: launch/trust match: trust, workspace coverage
- `mac/66TaskLight/Sources/TaskLightCore/TaskLightStore.swift`: launch/trust match: trust
- `mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift`: launch/trust match: trust
- `script/check_codex_hooks_trust.py`: launch/trust match: path, trust
- `script/check_codex_thread_coverage.py`: launch/trust match: trust
- `script/check_codex_workspaces_coverage.py`: launch/trust match: trust, workspace coverage
- `script/install_hooks_for_workspace.sh`: launch/trust match: path
- `script/install_hooks_for_workspaces.sh`: launch/trust match: path, trust
- `script/smoke_hooks_config.sh`: launch/trust match: trust
- `script/smoke_status_reflection_cases.sh`: launch/trust match: trust
- `script/smoke_workspace_coverage.sh`: launch/trust match: path

## Suggested Command
```bash
python3 script/self-review/run_self_review.py --task-id M3.5 --task-type docs --task-type launch_agent --task-type release_audit --task-type swift_ui --scope-file /Users/macmini-simon66/Documents/Codex状态桌面栏提醒/docs/reports/self-review/M3.5/self-review-scope.json --evidence-profile full --mode final
```

## Human Review Warning
- Launch/trust or auth/secret risk exists. Do not auto-apply this scope without review.
