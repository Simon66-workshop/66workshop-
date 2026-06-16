# Scope Candidate M3.4c-sample

- Task ID: `M3.4c-sample`
- Task Types: `hook_bridge, state_projector`
- Generated At: `2026-06-16T08:46:20Z`
- Recommended Decision: `PASS`

## Recommended Include Paths
- `README.md`
- `config/self-review/`
- `docs/HOOK_BRIDGE_LAUNCH_AGENT.md`
- `docs/HOOK_SIGNAL_BRIDGE.md`
- `docs/STATE_PROJECTOR.md`
- `docs/STATUS_PROTOCOL.md`
- `docs/self-review/`
- `mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift`
- `mac/66TaskLight/Sources/TaskLightCore/TaskLightStore.swift`
- `mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift`
- `script/check_hook_bridge.sh`
- `script/check_hook_bridge_launch_agent.sh`
- `script/check_state_projector.sh`
- `script/hook_signal_bridge.py`
- `script/install_hook_bridge_launch_agent.sh`
- `script/install_state_projector_launch_agent.sh`
- `script/self-review/`
- `script/smoke_hook_bridge_launch_agent.sh`
- `script/smoke_hook_signal_bridge.sh`
- `script/smoke_self_review.sh`
- `script/smoke_self_review_generate_scope.sh`
- `script/smoke_self_review_scope.sh`
- `script/smoke_state_projector.sh`
- `script/smoke_turn_runtime_arbiter.sh`
- `script/state_projector.py`
- `script/uninstall_hook_bridge_launch_agent.sh`
- `script/uninstall_state_projector_launch_agent.sh`

## Recommended Exclude Paths
- none

## In-Scope Candidate Files
- `config/self-review/scoring-rubrics.json`
- `script/self-review/run_self_review.py`

## Out-of-Scope Dirty Files
- none

## Risk Classification
- `risky_launch_trust`: `0`
- `risky_auth_secret`: `0`
- `build_artifacts`: `0`
- `cache_artifacts`: `0`
- `docs_assets`: `0`
- `app_assets`: `0`
- `unknown`: `0`

## Why Risky Files Were Classified
- none

## Suggested Command
```bash
python3 script/self-review/run_self_review.py --task-id M3.4c-sample --task-type hook_bridge --task-type state_projector --scope-file /Users/macmini-simon66/Documents/Codex状态桌面栏提醒/docs/reports/self-review/M3.4c-sample/self-review-scope.json --evidence-profile full --mode final
```
