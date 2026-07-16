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

Each binding now keeps:

- `canonical_identity = "turn:<turn_id>"` as the primary projector identity
- `source_key = "hook:<session_id_or_unknown>:<turn_id>"` as the hook-side file key
- `aliases[]` for stronger follow-up joins such as `appserver:<thread_id>:<turn_id>`

This preserves one-turn-one-task semantics even when multiple turns share the
same thread.

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

The original hook signal that created the binding is also preserved as
`origin_signal_id`, so duplicate/late signals can be audited without reusing
thread-level identity.

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

`TASKLIGHT_HOOK_TURN_LEASE_SECONDS` defaults to `300`.

`TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS` defaults to `300`, aligned with
the bounded turn lease.

If an active turn binding has no fresh hook signal after the lease, the bridge
silently calls `tasklight release` only when the task is still active. This does
not play red or green sound and does not write `done_verified`.

`item_completed` means one tool item completed, not that the Codex turn ended.
It therefore keeps the same bounded lease as the turn by default. A trusted
`stop` remains the authoritative completion signal; if it is missing, the
300-second lease still releases the task fail-closed.

Completed-idle release is a soft timeout. The binding records
`release_kind=soft_timeout`, `released_by=completed_idle_timeout`, and
`allow_late_stop=true`. If a real `stop` hook arrives later for the same turn,
the bridge must recover the task to `done_unverified` instead of leaving it
cancelled.

## Stop Priority Guard

`stop` signals have higher priority than timeout release and heartbeat
coalescing:

- `stop` is never coalesced.
- `stop` is not ignored only because the turn binding was soft-released.
- `stop` after soft timeout writes `done_unverified`.
- repeated `stop` on `done_unverified` is idempotent.
- `stop` after `done_verified` is ignored and does not downgrade the task.
- `stop` after explicit blocked/tool-failed/approval-pending records a
  diagnostic and keeps the blocker.
- user clear/cancel remains hard-cancelled and is not recovered by late stop.

Processed decisions are explicit: `stop_to_done_unverified`,
`stop_idempotent_done_unverified`, `stop_ignored_already_verified`,
`stop_after_blocked_diagnostic`, or a specific ignored stop reason.

## Bridge Health

The bridge writes a read-only health sidecar after every bridge pass:

```text
~/.66tasklight/hook_bridge_health.json
```

The file records `status`, `last_run_at`, `last_seen_at`, processed counts,
released binding counts, active turn bindings, and the most recent local error.
The macOS App reads this file for the expanded diagnostic line only; health
status does not change the global lamp.

Override the path with:

```bash
TASKLIGHT_HOOK_BRIDGE_HEALTH_PATH=/path/to/hook_bridge_health.json
```

## State Projector Integration

M3.2a keeps the bridge as the managed task writer, but moves final LuckyCat
display decisions into `script/state_projector.py`.

The bridge still consumes hook signals and writes managed task state plus
`turn_bindings`, and it also emits normalized bridge decision signals into the
append-only signal bus. The projector reads `normalized_signals.jsonl` first,
then uses task files and turn bindings as enrichment/compatibility input to
produce `~/.66tasklight/ui_state.json`.

This split matters because a backend task can remain `running` while the UI
should stop showing RUNNING after the matching hook turn is no longer fresh. The
projector applies active hook TTL, completed-idle release projection, stale hook
blocker suppression, pending verification projection, and recent completion
windowing.

Swift should read `ui_state.json` for display instead of reimplementing these
rules.

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
