# 66TaskLight Self-Review Arbiter

M3.4 Phase 1 adds a local review gate that runs after implementation work and
produces a structured self-review report.

This engine is intentionally narrow:

- local only
- review only
- no auto fix
- no auto commit
- no auto push
- no external API

## Scope

Supported task types:

- `state_projector`
- `hook_bridge`
- `appserver_watcher`
- `observer`
- `swift_ui`
- `launch_agent`
- `signal_bus`
- `release_audit`
- `docs`

Each task type maps to a fixed auditor set plus evidence requirements from
`config/self-review/`.

## Phase 1 Flow

1. Collect a sanitized baseline from git state, `ui_state.json`, task files, and
   the normalized signal bus.
2. Optionally narrow the review to a scoped file set by `--scope-file`,
   `--review-path`, and `--exclude-path`.
2. Run required health and smoke commands.
3. Enforce hard safety boundaries.
4. Run domain auditors.
5. Score the candidate across state accuracy, arbitration safety, UI
   consistency, launch health, diagnostics, and maintainability.
6. Write a final review packet under `docs/reports/self-review/<task-id>/`.

## Hard Boundaries

The engine must reject or escalate when it sees:

- privacy boundary violations
- fake green paths
- missing required evidence
- failed `check_all.sh`
- build artifacts staged
- weak runtime signals promoted into `RUNNING`

## Outputs

Each report directory contains:

- `baseline.json`
- `baseline.md`
- `evidence.json`
- `evidence.md`
- `scope-summary.json`
- `score.json`
- `reflection.json`
- `final-review.md`

The report stores summaries and key facts only. It does not store prompt text,
response text, auth data, or raw log bodies.

## Scoped Review

Phase `M3.4a` adds scoped review so unrelated dirty worktree files do not
automatically contaminate the current task judgment.

CLI:

```bash
python3 script/self-review/run_self_review.py \
  --task-id M3.4a \
  --task-type state_projector \
  --scope-file /path/to/self-review-scope.json \
  --mode final
```

Scope file shape:

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

Decision rules:

- in-scope hard failures still `REJECT`
- out-of-scope ordinary dirty files degrade to scoped warning and usually
  `CONDITIONAL_PASS`
- out-of-scope launch/trust/security files become `NEEDS_HUMAN_REVIEW`
- out-of-scope auth/secret exposure still `REJECT`

## Evidence Profiles

Use `--evidence-profile` to trade coverage for speed:

- `fast` runs the lightweight compile + smoke + basic scope audit path.
- `full` keeps the current default behavior.
- `release` keeps `full` and adds a release-readiness audit.

Example:

```bash
python3 script/self-review/run_self_review.py \
  --task-id M3.4b \
  --task-type state_projector \
  --task-type hook_bridge \
  --scope-file /path/to/self-review-scope.json \
  --evidence-profile fast \
  --mode final
```
