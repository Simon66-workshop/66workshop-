# 66TaskLight Multi-Task Status Protocol

## Purpose

66TaskLight is a local-first task status bus for Codex and Hermes workflows on macOS.
It is offline-only, fail-closed, and designed for many concurrent wrappers without
overwriting each other.

## Storage Layout

Canonical files live under `~/.66tasklight/` by default:

- `state.json`
- `ui_state.json`
- `state_projector_health.json`
- `normalized_signals.jsonl`
- `tasks/<task_id>.json`
- `ui_clients/<pid>.json`
- `thread_bindings/<CODEX_THREAD_ID>.json`
- `turn_bindings/<safe_source_key>.json`
- `hook_bridge_offsets.json`
- `observations/<observation_id>.json`
- `observations_state.json`
- `events.jsonl`
- `played_events.json`
- `current.json` as a compatibility mirror for legacy single-task readers
- `.lock` for serialized writers

All paths, sound names, and refresh intervals are configurable through environment
variables:

- `TASKLIGHT_STATE_DIR`
- `TASKLIGHT_STATE_PATH`
- `TASKLIGHT_UI_STATE_PATH`
- `TASKLIGHT_UI_CLIENTS_DIR`
- `TASKLIGHT_STATE_PROJECTOR_HEALTH_PATH`
- `TASKLIGHT_NORMALIZED_SIGNALS_PATH`
- `TASKLIGHT_STATE_PROJECTOR_POLL_SECONDS`
- `TASKLIGHT_TASKS_DIR`
- `TASKLIGHT_CURRENT_PATH`
- `TASKLIGHT_THREAD_BINDINGS_DIR`
- `TASKLIGHT_TURN_BINDINGS_DIR`
- `TASKLIGHT_HOOK_BRIDGE_OFFSETS_PATH`
- `TASKLIGHT_SIGNAL_SPOOL_DIR`
- `TASKLIGHT_HOOK_TURN_LEASE_SECONDS`
- `TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS`
- `TASKLIGHT_HOOK_BRIDGE_POLL_SECONDS`
- `TASKLIGHT_EVENTS_PATH`
- `TASKLIGHT_PLAYED_EVENTS_PATH`
- `TASKLIGHT_LOCK_PATH`
- `TASKLIGHT_BLOCKED_SOUND`
- `TASKLIGHT_DONE_SOUND`
- `TASKLIGHT_STALE_SOUND` legacy/ignored in M2.1+; stale reuses the blocked/red lane
- `TASKLIGHT_OBSERVATIONS_DIR`
- `TASKLIGHT_OBSERVATIONS_STATE_PATH`
- `TASKLIGHT_TTL_SECONDS`
- `TASKLIGHT_VERIFICATION_TTL_SECONDS`
- `TASKLIGHT_REFRESH_SECONDS`

## Task States

Legal task states:

- `queued`
- `running`
- `blocked`
- `done_unverified`
- `done_verified`
- `stale`
- `cancelled`

Diagnostic only:

- `invalid_json`

`invalid_json` is not a normal transition state. It is used when a per-task JSON file
cannot be decoded. It must not poison the rest of the board.

## Per-Task File Schema

Each `tasks/<task_id>.json` file stores a single task record. Relevant fields include:

- `schema_version`
- `task_id`
- `short_task_id`
- `title`
- `slug`
- `status`
- `raw_status`
- `effective_status`
- `phase`
- `progress`
- `reason`
- `message`
- `evidence`
- `summary`
- `created_at`
- `started_at`
- `updated_at`
- `heartbeat_at`
- `done_at`
- `verified_at`
- `cancelled_at`
- `ttl_seconds`
- `source`
- `last_error`
- `current_event_id`
- `file_path`
- `alert_fingerprint`
- `sound_type`
- `is_invalid_json`
- `invalid_json_error`

`done_unverified` is the intermediate completion state. It means the task command
has ended, but the acceptance gate has not passed yet. It stays blue until verified
and must not trigger the green completion sound.

## Observation Layer

## Current Thread Binding

Current Codex desktop work can be bound explicitly to the managed path through a
thread sidecar file. This does not add a new task state and does not change the
authoritative task schema.

Sidecar path:

- `thread_bindings/<CODEX_THREAD_ID>.json`

The sidecar is keyed by `CODEX_THREAD_ID` and carries binding metadata such as:

- `thread_id`
- `task_id`
- `title`
- `cwd`
- `created_at`
- `updated_at`
- `phase`
- `progress`
- `watch_pid`
- `released_at`
- `status` (`active` or `released`)

The lease watcher is implemented as
`script/codex_current_task_watcher.py` and is started as a detached process. It
does not depend on a transient shell stdin payload. It calls
`script/codex_private_state_probe.py` when Codex local state is readable. The
probe emits metadata only and does not print prompts, responses, auth data, or
raw log bodies.

The binding sidecar is not part of `state.json` aggregation. It exists only to let
the current Codex session resolve the correct managed task id and keep a local
lease watcher alive. The watcher is bounded by
`TASKLIGHT_CURRENT_TASK_ACTIVE_LEASE_SECONDS` (default `45`). If the binding is
not updated within that lease, the watcher clears the managed task and marks the
binding `released`, so an idle Codex session does not remain blue indefinitely.
Private probe output is routed through signal fusion before any watcher action.
Only a fusion decision of `refresh_managed_heartbeat` may refresh the managed
heartbeat. Quiet decisions release the binding after repeated quiet samples, and
unknown decisions use a short lease fallback.

## Codex Signal Confidence

M3.0 introduces local signal fusion. Signal records may include:

- `source`
- `event_type`
- `thread_id`
- `turn_id`
- `item_id`
- `event_time`
- `confidence`
- `thread_scoped`
- `turn_scoped`
- `source_quality`
- `decision`
- `evidence`
- `conflicts`

Fusion output includes `inferred_status`, `decision`, `confidence`,
`authoritative`, `task_identity`, `signal_source`, `source_quality`,
`evidence`, and `conflicts`.

Private probe signals are fallback-only. A private signal may refresh managed
heartbeat only when it is thread-scoped and has confidence of at least `0.70`.
Global-only private metadata must not refresh managed heartbeat.

## Hook Signal Bridge

Trusted Codex hooks write local signal JSONL under `signals/*.jsonl`. The signal
spool itself is input only. `script/hook_signal_bridge.py` is the writer that
projects hook signals into managed tasklight tasks through the existing CLI.

The bridge enforces:

- `thread_id` is a conversation container, not a task,
- `turn_id` is the task execution unit,
- one `turn_id` maps to one tasklight `task_id`,
- signals without `turn_id` do not create managed tasks,
- `stop` maps only to `done_unverified`,
- `done_verified` still requires explicit `verify`.

Turn bindings live in `turn_bindings/<safe_source_key>.json`.

Required binding fields include:

- `schema_version`
- `source_key`
- `task_id`
- `thread_id`
- `turn_id`
- `session_id`
- `title`
- `cwd`
- `status` (`active` or `released`)
- `created_at`
- `updated_at`
- `last_signal_at`
- `last_signal_event`
- `phase`
- `signal_count`
- `released_at`
- `release_kind` (`soft_timeout`, `stop`, or `user_cancelled`)
- `released_by`
- `allow_late_stop`

`hook_bridge_offsets.json` stores file offsets, processed signal ids, and the
last processing timestamps so repeated bridge runs do not replay old events.

`TASKLIGHT_HOOK_TURN_LEASE_SECONDS` defaults to `60`. When an active turn binding
has no fresh signal beyond the lease, the bridge silently releases active tasks
with `sound_type=none`; it does not block, complete, or verify the task.

`TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS` defaults to `20`. If a hook turn's
last signal is `item_completed` and no `stop` follows, the bridge uses this
shorter window to release the active projection. When a newer hook turn is
active, older hook-projected tasks that have already become `stale` can also be
silently released so stale history does not mask the current running turn.

Completed-idle timeout is a soft release, not a verified completion and not a
hard user cancellation. Soft release records `release_kind=soft_timeout`,
`released_by=completed_idle_timeout`, and `allow_late_stop=true`. A later real
`stop` for the same turn may recover the task to `done_unverified` so LuckyCat
can show `PENDING`.

User clear/cancel is hard cancellation. It records or implies
`release_kind=user_cancelled` and `allow_late_stop=false`; a late stop must not
revive that task.

## Observation Layer

`observe-local` is a separate local discovery pass that watches running Codex child
processes which look like real task execution. It does not write `done_verified`
and does not change managed task state.

Observed thread files live under `observations/<observation_id>.json` and are
summarized in `observations_state.json`.

Observed statuses:

- `observed_active`
- `observed_quiet`
- `observed_attention`
- `observed_disappeared`

Rules:

- observed threads are display-only and never overwrite managed task records,
- observed threads default to silent audio,
- `observed_disappeared` is removed from the active board after a few missed scans,
- the whitelist only accepts `codex` CLI-shaped child processes such as
  `codex exec`, `codex run`, `codex chat`, `codex shell`, or `codex resume`,
- Codex Desktop infrastructure such as `app-server`, `node_repl`, `chronicle`,
  crash handlers, Computer Use, and Hermes gateway processes are excluded,
- if a scan sees `TASKLIGHT_TASK_ID=...`, the process is treated as managed-linked
  and is not duplicated in the observed board.

Global lamp interplay:

- managed `blocked` or `stale` still forces red,
- high-confidence `observed_attention` can also force red,
- managed running/pending or any active observed thread keeps the lamp blue,
- only managed verified completion can return the lamp to green when nothing else is active.

## Aggregate State Schema

`state.json` is the backend aggregate snapshot. It is rebuilt after every task
mutation and remains available for CLI, compatibility, and projector input.
LuckyCat uses `ui_state.json` as its final read model in M3.2a+.

Top-level fields include:

- `schema_version`
- `source`
- `source_health`
- `lamp_status`
- `global_status`
- `generated_at`
- `updated_at`
- `current_task_id`
- `last_verified_at`
- `last_event_at`
- `counts`
- `tasks`
- `invalid_tasks`

The `counts` object includes:

- `blocked`
- `stale`
- `running`
- `queued`
- `done_verified`
- `done_unverified`
- `pending_verify_count`
- `cancelled`
- `invalid_json`
- `active`
- `total`
- `red`
- `blue`
- `green`
- `gray`

## UI Read Model Schema

`ui_state.json` is produced by `script/state_projector.py` and is the final
LuckyCat read model. The projector reads task files, `state.json`, turn
bindings, observations, hook bridge health, and UI client diagnostics, then
atomically writes a single UI-safe snapshot.

Top-level fields include:

- `schema_version`
- `source`
- `projector_generated_at`
- `global_status`
- `lamp_status`
- `global_display_title`
- `state_confidence`
- `counts`
- `tasks`
- `observations`
- `diagnostics`

The `counts` object includes:

- `blocked`
- `stale`
- `running`
- `queued`
- `pending_verify_count`
- `done_verified_visible`
- `observed_active`
- `managed_active`

Task projections include `raw_status`, `effective_status`, `display_scope`,
`state_cause`, `fresh`, optional `turn_id`, and optional
`last_signal_age_sec`. Valid UI display scopes are:

- `active_execution`
- `open_blocker`
- `pending_verify`
- `recent_done`
- `history`
- `released`
- `invalid`

Projector diagnostics include hook bridge status, active turn binding count,
latest active turn age, latest observed age, mismatch warnings, state dir, app
bundle path, build id, and projector reasons.

`normalized_signals.jsonl` is a bounded sanitized diagnostic log generated by the
projector. It must not contain prompt, response, auth, or raw log body content.

`ui_clients/<pid>.json` is written by the app for diagnostics only. It records
pid, bundle path, executable path, build id, state dir, and timestamps. It is not
task state and must not affect task transitions.

## Global Lamp Rules

For LuckyCat, the compact lamp uses `ui_state.json`, not any single task file.

1. If any projected task has `display_scope=open_blocker`, the global lamp is red.
2. Else if any projected task has `display_scope=active_execution`, the lamp is blue.
3. Else if a fresh high-confidence observed thread is active, the lamp is blue.
4. Else if any projected task has `display_scope=pending_verify`, the lamp is pending.
5. Else if `done_verified_visible > 0`, the lamp is green.
6. Otherwise the lamp is gray/idle.
7. `invalid_json` is isolated and does not change the lamp on its own.

## Task Transition Rules

- `start` creates a new task id and writes a new task record as `running`.
- `heartbeat --task-id <id>` is valid for live active tasks and refreshes phase/progress.
- `done --task-id <id>` marks the task `done_unverified`.
- `verify --task-id <id>` promotes `done_unverified` to `done_verified`.
- `block --task-id <id> --reason <enum>` writes `blocked`.
- `clear --task-id <id>` marks `cancelled` and preserves history.

Blocker reasons must match exactly:

- `dirty_worktree`
- `missing_input`
- `test_failed`
- `acceptance_failed`
- `permission_denied`
- `timeout`
- `stale_state`
- `invalid_json`
- `codex_exit_failed`
- `needs_human_review`
- `hardware_missing`

Invalid transitions fail closed. When possible, they write a blocked or diagnostic
record instead of pretending success.

## TTL And Stale Behavior

`stale` is computed from `heartbeat_at` and the configured TTL for running tasks.
`done_unverified` uses `done_at` or `updated_at` plus
`TASKLIGHT_VERIFICATION_TTL_SECONDS`.

- If a running task exceeds TTL, the visible state becomes `stale`.
- If a `done_unverified` task exceeds the verification TTL, the visible state
  becomes `stale` and is treated as a red diagnostic state.
- The app must treat stale as red.
- `state.json` corruption is a separate health problem and must not crash the app.
- A corrupt task JSON becomes `invalid_json` for that task only.

## Atomicity Rules

- Task records, `state.json`, `ui_state.json`, and projector health files are
  written with atomic temp-file replace semantics.
- Current-thread binding sidecars use the same atomic temp-file replace rule.
- `events.jsonl` is append-only and each event is appended as one JSON line.
- Writers hold the file lock while mutating task records, appending events, and rebuilding
  the aggregate snapshot.
- No half-written JSON should ever be visible to a reader.

## Event Log Schema

Each `events.jsonl` row includes the required fields:

- `event_id`
- `task_id`
- `from`
- `to`
- `created_at`
- `sound_type`

Events may also carry `reason`, `message`, `summary`, `phase`, `progress`, and `title`
for traceability.

`sound_type` is used by the desktop app for red/green alert playback. Valid values are
`blocked`, `done_verified`, or `none`.
`done_unverified` must not emit an alert sound.

## Sound Ledger

`played_events.json` stores the durable audio dedupe ledger:

- `muted`
- `played_event_ids`
- `sound_windows`
- `updated_at`

The app uses this ledger to ensure:

- old events do not replay after restart,
- the same `event_id` never sounds twice,
- repeated blocked or verified-completion bursts within 5 seconds collapse into one sound.

`stale` is treated as a red diagnostic state. If a stale task needs to participate
in any audio path, it must reuse the blocked/red alert lane rather than introducing
a separate stale sound class.

## Compatibility Behavior

`current.json` remains as a compatibility mirror for older single-task flows.
It is not the authoritative source in M2.0.

`observations_state.json` is the authoritative snapshot for the observation layer
and is read separately from the managed task state.

Readers should prefer:

1. `ui_state.json` for LuckyCat and other UI consumers
2. `state.json` for backend aggregate compatibility
3. `tasks/<task_id>.json`
4. `observations_state.json` for observed threads
5. `current.json` as a legacy fallback

If `ui_state.json` is missing, stale, or unreadable, the app may generate a
degraded local fallback from `state.json` and task files, marking diagnostics
with `fallback_reason`. If `state.json` is unreadable, the app must fail closed
and show a stale or blocked diagnostic rather than crashing. If a single task
file is unreadable, isolate it as `invalid_json` and keep the rest of the board
visible.

## UI Skin Boundary

The LuckyCat 66VS macOS skin is a read-only presentation layer on top of the
existing protocol.

- it reads `ui_state.json` first,
- if the projector is unavailable, it may degrade to `state.json`,
  `observations_state.json`, per-task files, and legacy `current.json`,
- it must not write task state directly,
- it must not change the meaning of `done_unverified`, `done_verified`,
  `blocked`, `stale`, or any observed-thread status.

The app may write `ui_clients/<pid>.json` diagnostic metadata so local checks can
distinguish state errors from stale bundles, multiple app instances, or a desktop
shortcut pointing at the wrong bundle.
