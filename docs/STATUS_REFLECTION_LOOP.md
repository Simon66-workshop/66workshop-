# Status Reflection Loop

M3.4 adds a local loop for turning LuckyCat status mismatches into regression
fixtures.

It is diagnostic only. It does not change LuckyCat UI, does not write task
state, and does not change the State Projector priority rules.

## Commands

Capture the current mismatch:

```bash
./script/capture_status_mismatch.sh --expected running --note "other Codex workspace running but LuckyCat stayed DONE"
```

Create a fixture from a captured case:

```bash
python3 script/status_reflection_case.py fixture --case docs/status-reflections/cases/<case>.json
```

Or write recommended coverage fixtures directly:

```bash
./script/check_codex_thread_coverage.sh --write-recommended-fixtures
```

Use this when the question is specifically “why did LuckyCat not turn blue?” and
the coverage report already points at missing hooks, weak appserver evidence, or
process-only/private-probe signals.

Run regression checks:

```bash
./script/smoke_status_reflection_cases.sh
```

## What Gets Captured

Each case stores a sanitized summary:

- expected and actual UI status
- `ui_state.json` summary: status, title, counts, projector reason, top runtime
  candidate diagnostics
- `check_codex_thread_coverage.py` summary: coverage status, thread decisions,
  hook readiness, and recommended action
- `recommended_fixture`: a minimal, hashed fixture descriptor for the likely
  regression class

The case intentionally stores hashes for thread, turn, workspace, state path,
and signal path values. It does not store prompt text, response text, auth
content, or raw log bodies.

## Fixture Classes

- `missed_running`: expected `RUNNING`, but LuckyCat showed `DONE`, `IDLE`, or
  `BLOCKED`.
- `false_running`: LuckyCat showed `RUNNING`, but the expected state was not
  running.
- `false_blocked`: LuckyCat showed `BLOCKED`, but there was no current open
  blocker.
- `false_done`: LuckyCat showed `DONE`, but a fresh active turn should have
  taken priority.

## Why This Exists

Status mistakes are usually caused by missing reliable inputs, not by the cat
skin. Examples:

- `not running because workspace hooks missing`
- `not running because appserver evidence is notLoaded`
- `not running because only process_observer is present`
- `not running because only weak private probe evidence is present`

The reflection loop makes those explanations durable. A real mismatch can be
captured once, converted into a fixture, and then kept in smoke tests so the
same class of mistake does not return.

## Boundaries

- State Projector remains the only UI state judge.
- Raw `process_observer` and global-only private probe evidence remain
  diagnostic-only and must not drive global `RUNNING`.
- Fresh hook turn signals and fresh active-like appserver evidence remain the
  accepted paths for Codex runtime activity.
- `done_verified` still requires explicit verification.
- No external API is called by the reflection scripts.
