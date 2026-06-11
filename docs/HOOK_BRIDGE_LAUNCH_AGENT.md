# Hook Bridge LaunchAgent

M3.1c adds an optional user LaunchAgent for the Codex hook signal bridge.

The LaunchAgent keeps the bridge running outside the short-lived Codex command
executor process, so hook signals can be consumed continuously.

## Install

```bash
./script/install_hook_bridge_launch_agent.sh
```

Default values:

- label: `com.66tasklight.hook-bridge`
- plist: `~/Library/LaunchAgents/com.66tasklight.hook-bridge.plist`
- state dir: `~/.66tasklight`
- stdout log: `~/.66tasklight/logs/hook_bridge.out.log`
- stderr log: `~/.66tasklight/logs/hook_bridge.err.log`
- command: `python3 script/hook_signal_bridge.py --watch`

The plist sets `WorkingDirectory` to the project root:

```text
/Users/macmini-simon66/Documents/Codex状态桌面栏提醒
```

## Check

```bash
./script/check_hook_bridge_launch_agent.sh
```

The check prints:

- `plist_exists`
- `launchctl_status`
- `process_pid`
- `signal_dir`
- `latest_signal_age_sec`
- `active_turn_bindings`
- `latest_bridge_process_time`
- `log_tail`
- `STATUS`

`STATUS=ok` means the plist is loaded, a bridge process is running, and the
bridge offset file has refreshed recently. `STATUS=not_running` means the
LaunchAgent is absent or stopped. `STATUS=stale` means the process may be stuck.
`STATUS=error` means a local state file is unreadable.

## Uninstall

```bash
./script/uninstall_hook_bridge_launch_agent.sh
```

The uninstall script stops the user LaunchAgent and removes the plist. It does
not delete task state, signals, turn bindings, or logs.

## Environment

The installer forwards these environment variables into the plist when present:

- `TASKLIGHT_STATE_DIR`
- `TASKLIGHT_SIGNAL_SPOOL_DIR`
- `TASKLIGHT_TURN_BINDINGS_DIR`
- `TASKLIGHT_HOOK_BRIDGE_OFFSETS_PATH`
- `TASKLIGHT_HOOK_TURN_LEASE_SECONDS`
- `TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS`
- `TASKLIGHT_HOOK_BRIDGE_POLL_SECONDS`
- `TASKLIGHT_HOOK_BRIDGE_COALESCE_SECONDS`
- `TASKLIGHT_HOOK_SIGNAL_MAX_AGE_SECONDS`

`TASKLIGHT_HOOK_BRIDGE_COALESCE_SECONDS` defaults to `2`.

## Safety

The LaunchAgent does not call external APIs and does not read
`~/.codex/auth.json`.

The bridge consumes already-sanitized local hook signal JSONL and writes managed
task state only through the local `tasklight` CLI. It does not output prompt
text, response text, auth data, or raw log bodies.

`stop` still maps only to `done_unverified`. `done_verified` still requires an
explicit `tasklight verify`.
