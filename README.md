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
- five paw chips: `阻塞 / 运行 / 完成 / 待验 / 观察`
- left front paw must read as one continuous limb with the body shell, without visible seam breaks

This skin is read-only. It does not change protocol semantics, CLI writes,
sound rules, or observation behavior.

Status color mapping in the skin:

- `blocked` / `stale` -> red
- `running` / `queued` -> blue
- `done_unverified` -> amber label and blue global lamp contribution
- `done_verified` -> green
- visible observed threads -> cyan/blue display-only
- `idle` -> gray/gold

Title mapping follows the existing aggregate lamp logic:

- if any blocked/stale state is active, title is `BLOCKED`
- else if any running/queued/done_unverified/visible observed thread is active, title is `RUNNING`
- else if the global state is `done_verified`, title is `DONE`
- else title is `IDLE`

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
- the helper starts a lightweight background heartbeat watcher so long thinking
  time does not falsely turn the task stale
- `done`, `verify`, `block`, and `clear` stop the watcher and mark the thread
  binding as released
- `done` still only writes `done_unverified`; only `verify` can produce green

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
- `docs/SMOKE_TESTS.md` smoke test scenarios and expected matrix
- `script/smoke_observations.sh` live observation regression
- `docs/REAL_TRIAL.md` low-risk trial plan and what to log
