# Evidence

- evidence_profile: `release`
- required_command_ids: `check_all, check_hook_bridge_launch_agent, check_state_projector, check_ui_client, release_readiness`
- optional_command_ids: `smoke_appserver_thread_watcher, smoke_hook_signal_bridge, smoke_state_projector, smoke_turn_runtime_arbiter`
- required_passed: `5`
- optional_passed: `4`
- check_all_ran: `True`
- release_readiness: `{"appassets_ignored": false, "docs_assets_ignored": false, "ignored_paths": [], "release_ready": true, "staged_build_artifacts": []}`

## required_commands
- `check_all`: `pass` exit=`0` line=`Build of product 'TaskLightChecks' complete! (0.08s)`
- `check_hook_bridge_launch_agent`: `pass` exit=`0` line=`STATUS=ok`
- `check_state_projector`: `pass` exit=`0` line=`STATUS=ok`
- `check_ui_client`: `pass` exit=`0` line=`STATUS=ok`
- `release_readiness`: `pass` exit=`0` line=`release_readiness_audit: ok`

## optional_commands
- `smoke_appserver_thread_watcher`: `pass` exit=`0` line=`smoke_appserver_thread_watcher: ok`
- `smoke_hook_signal_bridge`: `pass` exit=`0` line=`smoke_hook_signal_bridge: ok`
- `smoke_state_projector`: `pass` exit=`0` line=`smoke_state_projector: ok`
- `smoke_turn_runtime_arbiter`: `pass` exit=`0` line=`smoke_turn_runtime_arbiter: ok`
