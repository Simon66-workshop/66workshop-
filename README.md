# 66TaskLight

66TaskLight is a local-first task status bus and floating macOS dashboard for
Codex / Hermes workflows.

It is offline-only, fail-closed, and supports many concurrent wrapper processes
without overwriting each other.

## What It Does

- Creates a fresh task id for every wrapper run
- Tracks `queued`, `running`, `blocked`, `done_unverified`, `done_verified`,
  `stale`, and `cancelled`
- Rebuilds a multi-task aggregate snapshot in `~/.66tasklight/state.json`
- Projects the final LuckyCat UI read model into `~/.66tasklight/ui_state.json`
- Keeps per-task JSON files in `~/.66tasklight/tasks/<task_id>.json`
- Keeps current-thread binding sidecars in `~/.66tasklight/thread_bindings/<CODEX_THREAD_ID>.json`
- Keeps live observation snapshots in `~/.66tasklight/observations/` and `~/.66tasklight/observations_state.json`
- Appends traceable events to `~/.66tasklight/events.jsonl`
- Deduplicates audio playback with `~/.66tasklight/played_events.json`
- Shows a compact floating lamp and an expanded 66VS-style glass dashboard
- Uses the LuckyCat 66VS skin by default while keeping the old view only as a code fallback
- Treats `done_unverified` as blue/pending until `verify` succeeds or the
  verification TTL expires

## Install

Requirements:

- macOS
- Swift Command Line Tools
- Python 3

No external API calls are used.

The Swift app lives in `mac/66TaskLight` and is staged by
`script/build_and_run.sh`.

## Run

Launch the floating dashboard:

```bash
./script/build_and_run.sh
```

Verify that the bundle launches:

```bash
./script/build_and_run.sh --verify
```

The dashboard reads state from `~/.66tasklight/` by default. You can override
paths and timing with environment variables:

- `TASKLIGHT_STATE_DIR`
- `TASKLIGHT_STATE_PATH`
- `TASKLIGHT_TASKS_DIR`
- `TASKLIGHT_CURRENT_PATH`
- `TASKLIGHT_UI_STATE_PATH`
- `TASKLIGHT_UI_CLIENTS_DIR`
- `TASKLIGHT_THREAD_BINDINGS_DIR`
- `TASKLIGHT_EVENTS_PATH`
- `TASKLIGHT_PLAYED_EVENTS_PATH`
- `TASKLIGHT_LOCK_PATH`
- `TASKLIGHT_BLOCKED_SOUND`
- `TASKLIGHT_DONE_SOUND`
- `TASKLIGHT_STALE_SOUND` legacy/ignored in M2.1+; stale uses the blocked/red alert lane
- `TASKLIGHT_OBSERVATIONS_DIR`
- `TASKLIGHT_OBSERVATIONS_STATE_PATH`
- `TASKLIGHT_TTL_SECONDS`
- `TASKLIGHT_VERIFICATION_TTL_SECONDS`
- `TASKLIGHT_REFRESH_SECONDS`

## State Projector

LuckyCat now reads the final UI state from `~/.66tasklight/ui_state.json`.
`state.json` and `tasks/*.json` remain the backend compatibility model, but
Swift no longer decides the global red/blue/green/pending precedence itself.

Run the projector once:

```bash
python3 script/state_projector.py --once
```

Run it as a local watch process:

```bash
python3 script/state_projector.py --watch
```

Install it as a user LaunchAgent:

```bash
./script/install_state_projector_launch_agent.sh
```

Stop the LaunchAgent:

```bash
./script/uninstall_state_projector_launch_agent.sh
```

Check projector and app diagnostics:

```bash
./script/check_state_projector.sh
./script/check_ui_client.sh
```

The projector is read-only with respect to task state. It writes only
`ui_state.json` and `state_projector_health.json`. The append-only signal bus
in `normalized_signals.jsonl` is written by hook / observer / probe producers
and then consumed by the projector as the single UI truth input. The projector
does not read prompts, responses, auth files, or raw hook logs.

Once the signal bus is readable and non-empty, orphan `tasks/*.json` and
orphan `observations_state.json` records no longer drive the main lamp by
themselves. They stay available as compatibility/history diagnostics, while
fresh normalized signals remain the only source that can keep LuckyCat
`RUNNING` or `BLOCKED`. If the signal bus is missing or empty, the projector
still degrades back to those local files instead of dropping the UI to blank.
Open blockers are projected separately from stale and resolved blockers:
`open_blocker` is the only blocker scope that can force the global red lamp,
while `stale_blocker` and `resolved_blocker` stay visible for diagnosis without
holding the whole panel red forever.

M3.3 adds a Turn Runtime Arbiter inside the projector. All possible runtime
inputs become scored candidates before they can affect LuckyCat:

```text
runtime_score = base_confidence * freshness_score * identity_score * consistency_score
```

Only these candidates can drive the global blue lamp:

- fresh managed hook/wrapper/appserver turn projected as `active_execution`
- fresh appserver thread candidate projected as `observed_active_high_confidence`

These remain diagnostic/observation-only and must not independently drive
`RUNNING`:

- `process_observer` only
- global-only private probe metadata
- standalone current-thread watcher evidence

`ui_state.json` also carries writer identity metadata:
`projector_version`, `projector_pid`, `projector_code_hash`,
`projector_launch_label`, `projector_instance_id`, and
`diagnostics.writer_status`. Use `./script/check_state_projector.sh` to detect
old writers, stale output, or multiple projector processes.

For live display, Swift now treats `ui_state.json` as the only status truth.
It still keeps a degraded fallback path when the projector is missing or stale,
but it no longer re-opens hook bridge or thread-binding sidecars just to decide
the current lamp/title.
That degraded path is still packaged as a full `TaskLightUIState(source=swift_fallback)`,
so `TaskLightViewModel` keeps rendering from one read model instead of mixing
`ui_state.json` with old dashboard objects.

Signal bus retention is local and bounded:

- `TASKLIGHT_SIGNAL_BUS_MAX_RECORDS`
- `TASKLIGHT_SIGNAL_BUS_RETENTION_SECONDS`
- `TASKLIGHT_SIGNAL_BUS_MAX_BYTES`

When the bus file crosses the byte threshold, the writer compacts it under the
same lock, keeping only recent valid signals.

## Self-Review Arbiter

Phase `M3.4` adds a local Self-Review Arbiter for structured post-task review.
It is review-only:

- no external API
- no auth-file reads
- no auto commit or push
- no automatic code repair

Run a full review:

```bash
python3 script/self-review/run_self_review.py --task-id M3.4 --task-type state_projector --task-type hook_bridge --evidence-profile full --mode final
```

Run a scoped review when the working tree already contains unrelated dirty
files:

```bash
python3 script/self-review/run_self_review.py \
  --task-id M3.4a \
  --task-type state_projector \
  --task-type hook_bridge \
  --scope-file /path/to/self-review-scope.json \
  --evidence-profile full \
  --mode final
```

The scope file can include only the current task paths while excluding build
artifacts:

```json
{
  "task_id": "M3.4a",
  "include": [
    "script/self-review/",
    "config/self-review/",
    "docs/self-review/",
    "script/smoke_self_review.sh"
  ],
  "exclude": [
    "dist/",
    "mac/66TaskLight/.build/",
    "__pycache__/"
  ],
  "reason": "Limit review to Self-Review Arbiter Phase 1 files."
}
```

Recommended flow when the working tree already contains unrelated dirty files:

```bash
python3 script/self-review/generate_scope.py \
  --task-id M3.4c \
  --task-type state_projector \
  --task-type hook_bridge \
  --write-scope-file

cat docs/reports/self-review/M3.4c/scope-candidate.md

python3 script/self-review/run_self_review.py \
  --task-id M3.4c \
  --task-type state_projector \
  --task-type hook_bridge \
  --scope-file docs/reports/self-review/M3.4c/self-review-scope.json \
  --evidence-profile full \
  --mode final
```

The generator only recommends a scope candidate. It does not auto-apply the
scope, auto commit, or auto push.

Profile choices:

- `fast` for lighter scoped reviews.
- `full` for the current default review depth.
- `release` for full review plus release-readiness audit.

Outputs land in `docs/reports/self-review/<task-id>/`.
Each report also writes `scope-summary.json` alongside `final-review.md`.

## Observer

`observe-local` is a separate local discovery loop for live Codex child
processes that look like real task execution. It is display-only and never
writes managed task completion.

Manual watch:

```bash
./tasklight observe-local --watch
```

LaunchAgent install:

```bash
./script/install_observer_launch_agent.sh
```

This installs a user LaunchAgent, so the observer starts automatically after
you log in again.

Stop the LaunchAgent:

```bash
./script/uninstall_observer_launch_agent.sh
```

Health check:

```bash
./script/check_observer.sh
```

The observer can be left running while the App is closed. The App reads
`observations_state.json` and does not need to scan processes itself.

The observer now uses a whitelist classifier:

- it only accepts `codex` CLI-shaped child processes such as `codex exec` or
  `codex run`
- it excludes Codex Desktop infrastructure such as `app-server`, `node_repl`,
  `chronicle`, crash handlers, Computer Use, and Hermes gateway processes
- it remains a fallback layer; it does not replace explicit managed binding

## LuckyCat Skin

The default macOS skin is the LuckyCat 66VS dashboard:

- compact panel `360 x 220`
- expanded panel `680 x 500`
- compact panel keeps the cat face and counters visually clean; the primary status readout lives in the bottom status strip
- compact bottom status strip:
  - one continuous cream/champagne band
  - center orb sits above the band and inside the gold ring
  - left label shows the global status title such as `BLOCKED`
  - right label shows the compact `M...` time/count readout
  - status color glow must not bleed horizontally beyond the orb
- five paw chips are live state counters: `阻塞 = blocked + stale`, `运行 = running + queued`, `完成 = recently visible done_verified`, `待验 = pending_verify_count / done_unverified`, `观察 = visible observed_active threads`
- left front paw must read as one continuous limb with the body shell, without visible seam breaks

The compact `完成` paw is intentionally not an all-time history counter. It counts
`done_verified` tasks inside the visible completion window, defaulting to 24
hours. Override the window with `TASKLIGHT_DONE_VISIBLE_HOURS`.

This skin is read-only. It does not change protocol semantics, CLI writes,
sound rules, or observation behavior.

Status color mapping in the skin:

- `blocked` / `stale` -> red
- `running` / `queued` -> blue
- `done_unverified` -> amber label and blue global lamp contribution
- `done_verified` -> green
- observed/process/appserver diagnostics -> cyan/blue display-only
- `idle` -> gray/gold

Title mapping is presentation-only and avoids labeling pending verification as
active execution:

- if any blocked/stale state is active, title is `BLOCKED`
- else if any running/queued managed task is active, title is `RUNNING`
- else if a fresh high-confidence appserver runtime candidate is active, title is `RUNNING`
- else if only `done_unverified` tasks are active, title is `PENDING`
- else if the global state is `done_verified`, title is `DONE`
- else title is `IDLE`

Raw `process_observer` records and weak/global-only private probe observations
can increase observation diagnostics or the cyan paw count, but they do not
drive the main `RUNNING` title or blue lamp by themselves.

## Figma Backup

LuckyCat UI components were also staged as a Figma backup component library.

- file: `66TaskLight LuckyCat UI Backup`
- file key: `AZVStgfzyqylKVBkSVh8zJ`
- url: <https://www.figma.com/design/AZVStgfzyqylKVBkSVh8zJ>

Component mapping summary:

- `66TaskLight/LuckyCatPanel`
- `66TaskLight/CatMascot`
- `66TaskLight/StatusOrb`
- `66TaskLight/PawCounterChip`
- `66TaskLight/TaskCard`
- `66TaskLight/ObservedThreadCard`
- `66TaskLight/GlassSurface`

Component sizes come from `design/luckycat-ui/params/luckycat_layout.json`.
Color tokens come from `design/luckycat-ui/params/luckycat_tokens.json`.
State variants come from `design/luckycat-ui/params/status_mapping.json`.
The fuller component naming and variant table lives in
`docs/LUCKYCAT_FIGMA_COMPONENTS.md`.

## CLI

The Python CLI is the authoritative writer.

```bash
./tasklight start --title "Demo task" --print-id
./tasklight heartbeat --task-id <task_id> --phase build --progress 0.3
./tasklight block --task-id <task_id> --reason missing_input --message "Missing input" --evidence "log"
./tasklight done --task-id <task_id> --summary "Implementation finished"
./tasklight verify --task-id <task_id>
./tasklight clear --task-id <task_id>
./tasklight list
./tasklight show <task_id>
./tasklight status
./tasklight observe-local
./tasklight observe-local --watch
./tasklight observations
./tasklight clear-observations
```

`done` marks `done_unverified`. `verify` is the explicit promotion to
`done_verified`. `done_unverified` stays blue and shows as `待验收` in the
dashboard until it is verified or times out.

`observe-local` scans the local machine for whitelisted Codex child processes and
writes `observations_state.json`. It does not change managed task records. Run
`observe-local --watch` if you want a local discovery loop to keep the observation
snapshot fresh.

## Current Codex Session Binding

If you want the current Codex desktop thread to map cleanly into the managed
task path, bind the thread explicitly instead of relying on observer guesses.

The helper below requires `CODEX_THREAD_ID` and writes a sidecar under
`~/.66tasklight/thread_bindings/`.

```bash
./script/codex_current_task.sh start --title "Codex live task" --phase ui_polish --progress 0.2
./script/codex_current_task.sh heartbeat --phase ui_polish --progress 0.6
./script/codex_current_task.sh done --summary "Implementation finished"
./script/codex_current_task.sh verify
./script/codex_current_task.sh show
```

Behavior:

- `start` creates or reuses the current thread's managed task
- the helper starts a lightweight background lease watcher so quiet sessions are
  cleared instead of being kept alive as false running tasks
- the watcher runs from `script/codex_current_task_watcher.py` as a detached
  process, so it can outlive the short shell command that created the binding
- the watcher is now signal-only: it appends fresh `heartbeat` / `release`
  signals into `normalized_signals.jsonl` and updates `thread_bindings`, while
  the State Projector decides whether LuckyCat should still show `RUNNING`
- if no fresh current-thread signal survives
  `TASKLIGHT_CURRENT_TASK_ACTIVE_LEASE_SECONDS` (default `45`), the watcher
  marks the binding released so the projector can drop the task from active UI
  scope without forcing a fake backend cancellation
- when readable Codex private local state is available, the watcher calls
  `script/codex_private_state_probe.py`; only `active` probe results can refresh
  the current-thread active signal, while `quiet` probe results release the binding
- `done`, `verify`, `block`, and `clear` stop the watcher and mark the thread
  binding as released
- `done` still only writes `done_unverified`; only `verify` can produce green

Expanded diagnostics now expose current-thread freshness directly from
`ui_state.json`:

- current-thread binding status
- current-thread binding freshness
- latest current-thread binding age
- latest current-thread watcher signal age
- signal bus record count and per-source counts
- current-thread signal source / confidence / fusion decision
- latest turn binding event and latest bridge decision
- latest private-probe signal age / status / quality
- latest observer signal age from the normalized signal bus

Safe private-state probe:

```bash
./script/codex_private_state_probe.py --thread-id "$CODEX_THREAD_ID"
```

The probe reports metadata only: recent log age, process liveness, shell snapshot
age, and `active` / `quiet` / `unknown`. It does not print prompts, responses, or
auth data.

### Status Signal Confidence

M3.0 fuses multiple local signals instead of letting private metadata directly
drive the desktop light:

1. explicit tasklight helper / wrapper events
2. Codex App Server JSON-RPC events
3. Codex hooks events
4. Codex cloud stub fixtures, never called by default
5. private Codex local metadata probe
6. process observer

Only authoritative signals, or private signals with `thread_scoped=true` and
`confidence>=0.70`, may refresh a managed heartbeat. Global-only private log
activity is display-only fallback evidence and cannot keep the panel blue.

Useful local checks:

```bash
./script/codex_appserver_bridge.py --probe
./script/codex_appserver_bridge.py --listen --timeout 3 --thread-id "$CODEX_THREAD_ID"
./script/codex_private_state_probe.py --thread-id "$CODEX_THREAD_ID"
./script/codex_signal_fusion.py --input signals.json
```

The expanded LuckyCat dashboard shows a small signal diagnostic line from the
current thread binding sidecar: signal source, source quality, confidence,
inferred status, and fusion decision. This is read-only UI metadata and does not
change task protocol semantics.

To install project-local Codex hook signals:

```bash
./script/install_codex_hooks_status_bridge.sh
```

This writes `.codex/hooks.json` and enables `[features].codex_hooks = true` in
the project `.codex/config.toml`. Restart or reload the Codex project thread for
hooks to be picked up. Hook `Stop` maps to `done_unverified`; `verify` is still
required for green.

Check whether the project hook configuration is present and executable:

```bash
./script/check_codex_hooks_trust.sh
./script/check_codex_hooks_trust.sh --json
```

The checker is read-only. It does not modify Codex trust, tasklight state, or
the Codex UI. It can report whether local config is valid and whether Codex
app-server currently lists the hooks as trusted or untrusted, but Codex project
hooks still require a manual trust confirmation in the Codex UI.

Detailed setup notes live in `docs/CODEX_HOOKS_SETUP.md`.

Bridge trusted hook signals into managed task state:

```bash
python3 script/hook_signal_bridge.py --once
python3 script/hook_signal_bridge.py --watch
./script/check_hook_bridge.sh
```

Optional LaunchAgent mode keeps the bridge alive after terminal commands exit:

```bash
./script/install_hook_bridge_launch_agent.sh
./script/check_hook_bridge_launch_agent.sh
./script/uninstall_hook_bridge_launch_agent.sh
```

The bridge consumes `~/.66tasklight/signals/*.jsonl` and writes managed tasks via
the normal `tasklight` CLI. It maps one Codex `turn_id` to one tasklight task.
Each turn binding keeps `canonical_identity=turn:<turn_id>` and can later add
aliases such as `appserver:<thread_id>:<turn_id>` without changing the original
task meaning.
`Stop` becomes `done_unverified`; only `tasklight verify` can make the LuckyCat
lamp green.

Heartbeat noise is coalesced by default: repeated heartbeat-style hook signals
for the same turn, phase, and progress write at most once per
`TASKLIGHT_HOOK_BRIDGE_COALESCE_SECONDS` window, default `2`. `blocked`,
`done_unverified`, and explicit `verify` are never coalesced.

If the last hook signal is `item_completed` and no `stop` arrives, the bridge
silently releases the turn after `TASKLIGHT_HOOK_COMPLETED_IDLE_RELEASE_SECONDS`
seconds, default `6`. This prevents a completed-but-missing-stop turn from
holding LuckyCat in `RUNNING`.

That timeout is a soft release only. If a real `Stop` hook arrives later for the
same turn, the bridge recovers the task to `done_unverified`, so LuckyCat shows
`PENDING`. `verify` is still the only path to green/DONE. User clear/cancel is a
hard cancellation and is not revived by late stop.

The bridge stores its local sidecars in:

- `~/.66tasklight/turn_bindings/`
- `~/.66tasklight/hook_bridge_offsets.json`
- `~/.66tasklight/hook_bridge_health.json`

Detailed bridge behavior lives in `docs/HOOK_SIGNAL_BRIDGE.md`. LaunchAgent
operation details live in `docs/HOOK_BRIDGE_LAUNCH_AGENT.md`.

## Multi-Workspace Coverage

Each Codex workspace needs its own project hooks. A trusted hook setup in this
66TaskLight repo does not automatically cover other Codex projects.

Run a read-only batch report:

```bash
./script/check_codex_workspaces_coverage.sh
```

Install hooks for every discovered workspace:

```bash
./script/install_hooks_for_workspaces.sh --all-discovered
```

Install only workspaces reported as missing or invalid:

```bash
./script/install_hooks_for_workspaces.sh --from-report
```

After installing hooks, open each affected Codex workspace and approve hooks in
the Codex UI. 66TaskLight does not bypass that trust prompt.

LuckyCat compact panel shortcut:

- triple-click the cat nose to run the read-only batch report,
- the small bubble near the cat feet shows the report summary,
- clicking the bubble opens `~/.66tasklight/workspace_coverage/latest.md`,
- the shortcut never installs hooks and never writes task state.

More detail: `docs/CODEX_WORKSPACE_ONBOARDING.md`.

## Wrapper Integration

Use `examples/codex_task_wrapper.sh` as the shell wrapper for Codex/Hermes runs.

Example:

```bash
examples/codex_task_wrapper.sh -- your_command_here
```

The wrapper:

- creates a fresh task id,
- sends periodic heartbeats,
- writes `codex_exit_failed` when the command exits non-zero,
- writes `acceptance_failed` when the acceptance step fails,
- only emits green after `verify`.

If a managed process exposes `TASKLIGHT_TASK_ID`, the observation layer treats it as
managed-linked and does not duplicate it in the live observed thread board.

For real Codex desktop work, use either:

1. `examples/codex_task_wrapper.sh` around an external command, or
2. `script/codex_current_task.sh` inside the current Codex thread

## Testing

Python unit tests:

```bash
python3 -m unittest discover -s cli/tests -p 'test_*.py'
```

Swift build:

```bash
(cd mac/66TaskLight && swift build)
```

Swift self-check executable:

```bash
(cd mac/66TaskLight && swift run TaskLightChecks)
```

One-shot validation on this machine:

```bash
./script/check_all.sh
```

## Real Trial Flow

Use this flow when you want to exercise the system the same way a wrapper process
will use it:

```bash
./script/smoke_multitask.sh
./script/smoke_verify_gate.sh
./script/smoke_ttl.sh
./script/smoke_observations.sh
./script/smoke_current_thread_binding.sh
./script/smoke_hooks_config.sh
./script/smoke_hook_signal_bridge.sh
./script/smoke_workspace_coverage.sh
./script/check_all.sh
```

`check_all.sh` includes the smoke suite and does not require any manual sound
validation to pass. If you want to do a human speaker check, run it separately
after the automated smoke scripts.

`TASKLIGHT_STALE_SOUND` is kept only for legacy compatibility. In M2.1+ the app
uses the blocked/red alert lane for stale diagnostics instead of a separate stale
sound type.

`observations_state.json` is the separate live discovery snapshot. It is read by the
app as a display-only layer and is not used to write managed task completion.

`swift test` is intentionally not used here because the current Command Line
Tools install does not provide the XCTest / new Testing path used by the repo.
`TaskLightChecks` is the supported Swift-side validation executable.

## Troubleshooting

- If a task JSON file is corrupt, only that task becomes `invalid_json`.
- If `state.json` is corrupt, the app falls back to a stale diagnostic view.
- `blocked` and `stale` always render red.
- `done_verified` is the only green state.
- `done_unverified` stays blue until explicit verification.
- Missing heartbeats eventually become `stale`.
- `TASKLIGHT_STALE_SOUND` is legacy-only and does not define a separate stale lane.
- `observe-local` is local-only; it does not contact external APIs or read any
  Codex private database.
- The app does not call external APIs.

## Project Layout

- `cli/tasklight.py` authoritative CLI and state writer
- `cli/tests/test_tasklight.py` Python unit tests
- `docs/STATUS_PROTOCOL.md` protocol and schema definition
- `examples/codex_task_wrapper.sh` task wrapper
- `mac/66TaskLight` SwiftPM app bundle
- `script/build_and_run.sh` kill + build + run entrypoint
- `script/check_all.sh` one-shot validation
- `script/check_codex_hooks_trust.sh` read-only Codex hooks readiness check
- `script/check_codex_workspaces_coverage.sh` read-only multi-workspace coverage report
- `script/install_hooks_for_workspaces.sh` batch hook installer for discovered workspaces
- `script/hook_signal_bridge.py` bridge from trusted hook signals to managed tasks
- `script/check_hook_bridge.sh` hook bridge status check
- `docs/SMOKE_TESTS.md` smoke test scenarios and expected matrix
- `script/smoke_observations.sh` live observation regression
- `docs/REAL_TRIAL.md` low-risk trial plan and what to log
