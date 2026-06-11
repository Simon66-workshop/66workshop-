# Hook Signal Bridge

`hook_signal_bridge.py` connects trusted Codex hook signals to the managed
tasklight bus.

The hook converter only writes local signal JSONL. The bridge is the component
that turns those signals into managed tasks.

## Model

- Codex thread: conversation container
- Codex turn: one user request / agent execution unit
- tasklight task: local visual projection of one turn

The bridge maps one `turn_id` to one `task_id`.

`thread_id` must not be treated as a task id. If a later signal includes both
`thread_id` and `turn_id`, the bridge records an alias, but the turn binding
remains keyed by `turn_id`.

## Commands

Consume once:

```bash
python3 script/hook_signal_bridge.py --once
```

Watch continuously:

```bash
python3 script/hook_signal_bridge.py --watch
```

Install the user LaunchAgent:

```bash
./script/install_hook_bridge_launch_agent.sh
```

Check the LaunchAgent:

```bash
./script/check_hook_bridge_launch_agent.sh
```

Uninstall the LaunchAgent:

```bash
./script/uninstall_hook_bridge_launch_agent.sh
```

Check bridge health:

```bash
./script/check_hook_bridge.sh
```

## Files

Default files under `~/.66tasklight/`:

- `signals/*.jsonl`: input from trusted Codex hooks
- `turn_bindings/<safe_source_key>.json`: turn to task binding
- `hook_bridge_offsets.json`: consumed offsets and dedupe ledger

Default source key:

```text
hook:<session_id_or_unknown>:<turn_id>
```

`hook:unknown:<turn_id>` is valid in this release. Some hook payloads do not
carry stable `session_id` or `thread_id`; the bridge still keys managed tasks by
`turn_id` to avoid reviving old thread-level tasks. Future signals can add
aliases without changing the primary binding.

If `thread_id` exists, an alias may be recorded:

```text
appserver:<thread_id>:<turn_id>
```

## Event Mapping

| Hook signal | Managed task action |
| --- | --- |
| `turn_started` | create or reuse task, heartbeat `phase=turn_started` |
| `item_started` | heartbeat `phase=tool_running` |
| `item_completed` | heartbeat `phase=item_completed`; never done |
| `approval_pending` | block `needs_human_review` |
| `tool_failed` | block `codex_exit_failed` |
| `stop` | `done_unverified`; never `done_verified` |

Missing `turn_id` is ignored for managed tasks. This prevents thread-level or
global signals from creating false running state.

## Heartbeat Coalescing

`TASKLIGHT_HOOK_BRIDGE_COALESCE_SECONDS` defaults to `2`.

The bridge coalesces only heartbeat-style active signals:

- `turn_started`
- `item_started`
- `item_completed`

For the same `turn_id`, phase, task id, and progress value, only one heartbeat is
written during the coalescing window. The signal is still marked processed in
`hook_bridge_offsets.json` with decision `heartbeat_coalesced`, so it will not be
replayed.

Signals that can change user-visible correctness are never coalesced:

- `approval_pending`
- `tool_failed`
- `stop`
- explicit `verify`
- terminal-state ignores

This keeps LuckyCat blue during active work while reducing repeated
`events.jsonl` heartbeat noise from high-frequency hook events.

## Release Behavior

`TASKLIGHT_HOOK_TURN_LEASE_SECONDS` defaults to `60`.

`TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS` defaults to `20`.

If an active turn binding has no fresh hook signal after the lease, the bridge
silently calls `tasklight release` only when the task is still active. This does
not play red or green sound and does not write `done_verified`.

If the last signal is `item_completed`, the shorter completed-idle release window
is used. This fail-closed behavior prevents turns that finished tool activity but
missed a `stop` hook from keeping LuckyCat in `RUNNING` indefinitely.

When a newer hook turn is active, older hook-projected tasks that are already
`done_unverified` or `stale` are also silently released. This keeps a previous
unverified hook turn from forcing the global lamp red while the current Codex
turn is actively running. The release uses `sound_type=none` and does not mark
the old task verified.

Terminal tasks are never revived. If a task is already `done_unverified`,
`done_verified`, `blocked`, or `cancelled`, later active hook signals for the
same turn are ignored.

## LaunchAgent

The optional user LaunchAgent uses label `com.66tasklight.hook-bridge` and runs:

```bash
python3 script/hook_signal_bridge.py --watch
```

It writes logs to:

```text
~/.66tasklight/logs/hook_bridge.out.log
~/.66tasklight/logs/hook_bridge.err.log
```

The App remains read-only. The LaunchAgent only runs the local bridge, and the
bridge still writes managed state through the `tasklight` CLI.

## Safety

The bridge does not read prompt text, response text, auth files, or raw log
bodies. Evidence written into blocked tasks is limited to signal metadata:
source, event type, turn id, item id, event time, and hook event name.
