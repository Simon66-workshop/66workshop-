# State Projector

M3.2a adds a local UI read model for LuckyCat:

```text
tasks / state / turn_bindings / observations / bridge health / ui_clients
  -> script/state_projector.py
  -> ~/.66tasklight/ui_state.json
  -> LuckyCat
```

The projector is read-only with respect to task state. It does not call
`tasklight release`, `block`, `done`, or `verify`. It only writes
`ui_state.json`, `state_projector_health.json`, and bounded diagnostic
`normalized_signals.jsonl`.

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
- `done_unverified` projects to `pending_verify`; it does not become green.
- `done_verified` is counted in compact only inside
  `TASKLIGHT_DONE_VISIBLE_HOURS`, default `24`.
- Explicit wrapper blocked/stale tasks still force red.
- Stale hook blockers do not hold the global lamp red forever.
- Observed threads affect RUNNING only when fresh, whitelisted, and confidence is
  at least `0.70`.

## Global Status

The projector computes the global status in one place:

1. Any `open_blocker` -> `BLOCKED`
2. Any `active_execution` -> `RUNNING`
3. Fresh high-confidence observed active -> `RUNNING`
4. Any `pending_verify` -> `PENDING`
5. Any visible recent verified completion -> `DONE`
6. Otherwise -> `IDLE`

Swift should not reimplement this status precedence. LuckyCat reads
`global_display_title`, `lamp_status`, and `counts` from `ui_state.json`.

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
