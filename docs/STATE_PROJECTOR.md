# State Projector

M3.2a and M3.2b add a local UI read model for LuckyCat:

```text
normalized_signals.jsonl + turn_bindings + tasks + observations + bridge health + ui_clients
  -> script/state_projector.py
  -> ~/.66tasklight/ui_state.json
  -> LuckyCat
```

The projector is read-only with respect to task state. It does not call
`tasklight release`, `block`, `done`, or `verify`. It only writes
`ui_state.json` and `state_projector_health.json`.

`normalized_signals.jsonl` is the append-only local signal bus. Hook, observer,
probe, and explicit task writers dual-write into that bus; the projector reads
it as the primary input for UI state, then uses task files, turn bindings, and
observation sidecars only for enrichment, compatibility, and diagnostics.

When the signal bus is readable and has records, orphan task files and orphan
observation sidecars that have no matching normalized signal no longer drive
the LuckyCat lamp by themselves. They are downgraded to compatibility /
history scopes so old `running` or `blocked` files do not keep the UI blue or
red after fresh signals have moved on. If the signal bus is missing or empty,
the projector still falls back to task files and observation sidecars so the
UI degrades instead of going blank.

The signal bus is bounded locally with:

- `TASKLIGHT_SIGNAL_BUS_MAX_RECORDS`
- `TASKLIGHT_SIGNAL_BUS_RETENTION_SECONDS`
- `TASKLIGHT_SIGNAL_BUS_MAX_BYTES`

Compaction happens inside the signal writer lock. The projector only reads the
bounded bus; it does not compact it itself.

## Commands

Run once:

```bash
python3 script/state_projector.py --once
```

Run continuously:

```bash
python3 script/state_projector.py --watch
```

Install the user LaunchAgent:

```bash
./script/install_state_projector_launch_agent.sh
```

Check health:

```bash
./script/check_state_projector.sh
./script/check_ui_client.sh
```

Uninstall:

```bash
./script/uninstall_state_projector_launch_agent.sh
```

## UI State Schema

`~/.66tasklight/ui_state.json` is the final LuckyCat read model:

```json
{
  "schema_version": "0.1",
  "source": "state_projector",
  "projector_generated_at": "2026-06-11T08:00:00Z",
  "global_status": "running",
  "lamp_status": "running",
  "global_display_title": "RUNNING",
  "state_confidence": 0.95,
  "counts": {
    "blocked": 0,
    "stale": 0,
    "running": 1,
    "queued": 0,
    "pending_verify_count": 0,
    "done_verified_visible": 1,
    "observed_active": 0,
    "managed_active": 1
  },
  "tasks": [],
  "observations": [],
  "diagnostics": {
    "hook_bridge_status": "ok",
    "signal_bus_status": "readable",
    "latest_signal_age_sec": 1.2,
    "active_turn_bindings": 1,
    "latest_active_turn_age_sec": 2.1,
    "latest_observed_age_sec": null,
    "running_mismatch_warning": false,
    "state_dir": "~/.66tasklight",
    "app_bundle_path": null,
    "build_id": null,
    "projector_reason": ["active_execution"],
    "observed_false_positive_count": 0
  }
}
```

## Projection Rules

- Hook `running` only displays as active when a matching turn binding is active
  and fresh.
- `TASKLIGHT_HOOK_ACTIVE_DISPLAY_TTL_SECONDS` defaults to `12`.
- `item_completed` without a later `stop` is projected as released after
  `TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS`, default `20`.
- If a late `stop` arrives after a soft completed-idle release, Hook Bridge
  recovers the task to `done_unverified`; the projector then displays
  `pending_verify` and global title `PENDING`.
- Current-thread watcher bindings only remain active when there is a fresh
  watcher signal plus a fresh `thread_bindings/<CODEX_THREAD_ID>.json` record;
  stale current-thread `running` task files no longer keep LuckyCat blue by
  themselves.
- Legacy task files without any matching signal only affect the lamp when the
  signal bus is missing or empty. Once the signal bus is active, those orphan
  task files are projected as compatibility `released` / `resolved_blocker` /
  `history` rows instead of active lamp drivers.
- Legacy observation sidecars without `process_observer` signals are treated
  the same way: they remain visible for diagnosis, but they do not create
  `observed_active` while the signal bus is already active.

## Expanded Diagnostics

The expanded dashboard can now explain current-thread freshness from the
projected read model:

- `current_thread_binding_status`
- `current_thread_binding_fresh`
- `latest_current_thread_binding_age_sec`
- `latest_current_thread_signal_age_sec`
- `current_thread_task_identity`
- `current_thread_signal_source`
- `current_thread_signal_quality`
- `current_thread_signal_confidence`
- `current_thread_fusion_decision`
- `signal_bus_record_count`
- `signal_bus_source_counts`
- `latest_hook_signal_age_sec`
- `latest_hook_bridge_signal_age_sec`
- `latest_process_observer_signal_age_sec`
- `latest_private_probe_signal_age_sec`
- `latest_private_probe_status`
- `latest_private_probe_quality`
- `latest_turn_binding_canonical_identity`
- `latest_turn_binding_aliases`
- `binding_identity_count`
- `latest_turn_signal_event`
- `latest_bridge_decision`
- `done_unverified` projects to `pending_verify`; it does not become green.
- `done_verified` is counted in compact only inside
  `TASKLIGHT_DONE_VISIBLE_HOURS`, default `24`.
- Explicit wrapper blocked tasks still force red. Explicit stale tasks are
  projected as `stale_blocker` diagnostics and do not force the global lamp red.
- Stale hook blockers do not hold the global lamp red forever.
- Raw observed process records do not affect `RUNNING`; they only feed
  observation diagnostics and the observed paw count.
- Appserver observations affect `RUNNING` only when fresh, high-confidence, and
  backed by explicit active-like evidence such as `turn_started`,
  `item_started`, or `thread/list:status=active`.
- Global-only private probe metadata is diagnostic-only and does not affect
  `RUNNING`.
- Stale and resolved hook blockers remain visible in expanded diagnostics, but
  only `open_blocker` contributes to the global red lamp. `stale_blocker`
  still contributes to the compact red paw count through projector counts.

## M3.3 Turn Runtime Arbiter

M3.3 inserts a runtime-candidate layer between normalized signals and the final
LuckyCat lamp. The projector no longer lets each source independently decide
whether the UI is running.

Each runtime candidate includes:

- `candidate_id`
- `kind`
- `task_id`, `thread_id`, `turn_id`, `pid`
- `source_set`
- `last_signal_at`
- `last_event_type`
- `base_confidence`
- `freshness_score`
- `identity_score`
- `consistency_score`
- `runtime_score`
- `display_scope`
- `state_cause`
- `age_sec`
- `why_active`
- `why_ignored`
- `appserver_activity_evidence`

The score is:

```text
runtime_score = base_confidence * freshness_score * identity_score * consistency_score
```

Display thresholds:

- `active_execution`: `runtime_score >= 0.85`
- `observed_active_high_confidence`: `runtime_score >= 0.55`
- `observed_only`: `runtime_score >= 0.35`
- `ignored`: below `0.35`

Hard guards:

- `process_observer` alone can increase observation diagnostics, but cannot
  drive global `RUNNING`.
- global-only private probe metadata cannot drive global `RUNNING`.
- standalone current-thread watcher evidence cannot drive global `RUNNING`.
- appserver candidates may drive global `RUNNING` only when they are fresh,
  include active-like evidence, and score into
  `observed_active_high_confidence` or stronger.

`ui_state.json` exposes these candidates in `runtime_candidates`, and diagnostics
include `runtime_candidate_count`, `top_runtime_candidates`,
`appserver_active_count`, and `process_observed_count`.

## Writer Identity Guard

Every projector write includes:

- `projector_version`
- `projector_pid`
- `projector_executable_path`
- `projector_code_hash`
- `projector_launch_label`
- `projector_instance_id`

`check_state_projector.sh` compares the current script hash with
`ui_state.projector_code_hash` and reports `writer_status`:

- `ok`
- `old_writer`
- `multiple_writers`
- `stale`
- `error`

This separates real status mistakes from an old LaunchAgent or another projector
process still writing `ui_state.json`.

## Global Status

The projector computes the global status in one place:

1. Any `open_blocker` -> `BLOCKED`
2. Any managed/task `active_execution` -> `RUNNING`
3. Fresh `codex_appserver` runtime candidate with explicit active-like evidence
   and `observed_active_high_confidence` -> `RUNNING`
4. Any `pending_verify` -> `PENDING`
5. Any visible recent verified completion -> `DONE`
6. Otherwise -> `IDLE`

Swift should not reimplement this status precedence. LuckyCat reads
`global_display_title`, `lamp_status`, and `counts` from `ui_state.json`.
When the projector is unavailable, Swift still renders from a complete
`TaskLightUIState(source=swift_fallback)` object. It should not reopen raw
dashboard/task sidecars inside the view model and recompute the lamp there.

## UI Client Diagnostics

The app writes `~/.66tasklight/ui_clients/<pid>.json` at startup/refresh. This
file contains only diagnostic metadata:

- pid
- bundle id
- bundle path
- executable path
- build id
- state dir
- started/updated timestamps

It is not task state. Use `./script/check_ui_client.sh` to detect old app
bundles, multiple app instances, or a desktop alias pointing at the wrong bundle.
