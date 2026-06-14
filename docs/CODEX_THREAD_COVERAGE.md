# Codex Thread Coverage Inspector

`script/check_codex_thread_coverage.py` explains whether each locally observed
Codex thread has a reliable status input for 66TaskLight.

The inspector is read-only. It does not write task state, `ui_state.json`, or
LuckyCat UI files. It reads sanitized TaskLight sidecars and reports why a
thread can or cannot affect the main lamp.

M3.4 also emits a sanitized `recommended_fixture` in JSON output. That fixture
can be captured by `script/capture_status_mismatch.sh` and converted into a
status-reflection smoke case without saving prompt, response, auth, or raw log
body content.

M3.7 can also write those recommended fixtures directly when explicitly asked:

```bash
./script/check_codex_thread_coverage.sh --write-recommended-fixtures
```

The default report remains read-only. Fixture writing is only for regression
capture.

## Why Coverage Matters

Codex project hooks are loaded per workspace. A hook configuration in the
66TaskLight project does not automatically cover another Codex project. When a
thread runs in a workspace without trusted hooks, 66TaskLight may only see weak
signals such as app-server `notLoaded` or private probe metadata. Those signals
are diagnostic only and must not light the main lamp.

## Commands

```bash
./script/check_codex_thread_coverage.sh
./script/check_codex_thread_coverage.sh --json
./script/check_codex_thread_coverage.sh --workspace "/path/to/project"
./script/check_codex_thread_coverage.sh --write-recommended-fixtures
./script/install_hooks_for_workspace.sh "/path/to/project"
./script/capture_status_mismatch.sh --expected running --note "Codex is active but LuckyCat stayed DONE"
```

`install_hooks_for_workspace.sh` writes only:

- `<workspace>/.codex/hooks.json`
- `<workspace>/.codex/config.toml`

It points the workspace hook command at this project
`script/codex_hook_event.py` and keeps signals in
`~/.66tasklight/signals`.

## Decisions

- `covered_running`: fresh hook turn signal or fresh appserver active-like
  evidence. This can explain LuckyCat `RUNNING`.
- `covered_pending`: fresh stop/done-unverified evidence. This can explain
  LuckyCat `PENDING`.
- `diagnostic_only`: process observer, global private probe, or weak metadata.
  This never drives `RUNNING`.
- `uncovered_active_suspect`: a Codex thread is visible, but no authoritative
  signal is available. Install or trust hooks for that workspace.
- `stale`: old evidence outside the TTL. This does not affect the UI.

## Multi-Thread Check

1. Open two Codex workspaces.
2. Run `./script/install_hooks_for_workspace.sh "/path/to/workspace"` for each.
3. Restart or reload each Codex project so hooks are picked up.
4. Trigger a small turn in each workspace.
5. Run `./script/check_codex_thread_coverage.sh`.
6. Confirm the running thread reports `covered_running` or the report explains
   the missing hook/appserver evidence.

The inspector deliberately does not read `~/.codex/auth.json` and does not
print prompt, response, or raw log body content.
