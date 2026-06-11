# Codex Hooks Status Bridge

66TaskLight treats Codex hooks as local status signals. Hook events are converted
to tasklight signal JSON by:

```bash
script/codex_hook_event.py --event-json -
```

The converter must not write `done_verified`. Verification remains an explicit
tasklight transition.

## Hook Mapping

| Codex hook | tasklight signal | Meaning |
| --- | --- | --- |
| `SessionStart` | `turn_started` | A Codex session or turn became active. |
| `UserPromptSubmit` | `turn_started` | A user-submitted turn is active. |
| `PreToolUse` | `item_started` | A tool or command item started. |
| `PermissionRequest` | `approval_pending` | Blocks as `needs_human_review`. |
| `PostToolUse` success | `item_completed` | Item finished without failure. |
| `PostToolUse` failure | `tool_failed` | Blocks as `codex_exit_failed`. |
| `Stop` | `stop` | Maps to `done_unverified`, never green. |

## Signal Shape

Hook signals use the common signal schema:

- `source=codex_hook`
- `event_type`
- `thread_id`
- `turn_id`
- `item_id`
- `event_time`
- `confidence`
- `thread_scoped`
- `turn_scoped`
- `source_quality`
- `reason`
- `message`
- `evidence[]`
- `conflicts[]`

The signal must not include prompts, responses, auth material, or raw logs.

## Spool Mode

For future continuous integration, hook signals can be appended to a local spool:

```bash
script/codex_hook_event.py --event-json - --spool-dir ~/.66tasklight/signals
```

Project-local installation:

```bash
./script/install_codex_hooks_status_bridge.sh
```

The installer writes:

- `.codex/hooks.json`
- `.codex/config.toml` with `[features].codex_hooks = true`
- a local signal spool under `~/.66tasklight/signals`

Restart or reload the Codex project thread after installation. Existing running
threads may not pick up newly written project hooks immediately.

The current M3.0 watcher is conservative and does not require hooks to be
installed. Hooks are an authoritative input once present, but explicit tasklight
helper events still remain the highest priority.

Read-only readiness check:

```bash
./script/check_codex_hooks_trust.sh
```

The checker validates `.codex/hooks.json`, confirms that
`script/codex_hook_event.py --health` works, and optionally asks local Codex
app-server for hook trust metadata. It does not trust hooks automatically.

Manual trust setup and troubleshooting are documented in
`docs/CODEX_HOOKS_SETUP.md`.

## Managed Task Bridge

Hook signals do not directly change task state. After hooks are trusted, run the
bridge to project turn-scoped signals into the managed task bus:

```bash
python3 script/hook_signal_bridge.py --once
python3 script/hook_signal_bridge.py --watch
./script/check_hook_bridge.sh
```

The bridge reads `~/.66tasklight/signals/*.jsonl`, requires `turn_id`, and writes
task state only through the normal `tasklight` CLI.

Rules:

- `thread_id` is not a task id.
- one `turn_id` maps to one tasklight task.
- `PostToolUse` success is only a heartbeat.
- `PermissionRequest` blocks as `needs_human_review`.
- `Stop` writes `done_unverified`, never `done_verified`.
- `verify` remains the only green completion transition.

Full details are in `docs/HOOK_SIGNAL_BRIDGE.md`.
