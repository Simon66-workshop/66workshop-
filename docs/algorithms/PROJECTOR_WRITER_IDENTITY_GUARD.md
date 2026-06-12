# Projector Writer Identity Guard｜M3.3

## Problem

A stale LaunchAgent or old `state_projector.py` process may continue writing `ui_state.json` using old logic. This makes LuckyCat appear wrong even when the latest code is correct.

## Required Fields in `ui_state.json`

```json
{
  "projector_version": "M3.3",
  "projector_pid": 12345,
  "projector_executable_path": "/Users/.../script/state_projector.py",
  "projector_code_hash": "sha256:xxxx",
  "projector_launch_label": "com.66tasklight.state-projector",
  "projector_instance_id": "20260611-abc123"
}
```

## Reader Guard

Swift and check scripts must detect:

```text
source != state_projector             -> stale / fallback
projector_version < required_version  -> old_writer
projector_code_hash mismatch          -> old_writer
ui_state age too old                  -> stale
multiple state_projector.py processes -> multiple_writers
```

## Install Guard

`install_state_projector_launch_agent.sh` should:

1. unload old LaunchAgent
2. kill stale `state_projector.py` processes for this project root
3. install new plist
4. load new plist
5. wait for `ui_state.json`
6. verify `projector_code_hash` equals current script hash
7. print `projector_pid`, `projector_version`, `projector_code_hash`, and `writer_status`

## Check Output

`check_state_projector.sh` should print:

```text
projector_version=M3.3
projector_pid=...
projector_code_hash=...
expected_code_hash=...
writer_status=ok|old_writer|multiple_writers|stale
runtime_candidate_count=...
appserver_active_count=...
process_observed_count=...
top_runtime_candidates=...
```

