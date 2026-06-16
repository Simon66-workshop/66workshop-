# LuckyCat UI Read Model Refresh Fix

Date: 2026-06-15
Task: Fix LuckyCat main status display after projected state changes

## Summary

The observed symptom was a compact LuckyCat display showing `Done` while the projected read model already reported active work.

Current evidence before the fix showed:

- `ui_state.global_status=running`
- `ui_state.lamp_status=running`
- `tasklight status.global_status=running`
- `counts.running > 0`
- `diagnostics.running_mismatch_warning=true`

This pointed to a Swift UI presentation/refresh issue, not a State Projector decision failure.

## Root Cause

LuckyCat compact presentation used `global_display_title` directly for the visible title. If the title field lagged or became inconsistent with the projected status fields, the compact view could continue to show a stale title such as `Done` even though `global_status` and `lamp_status` were already `running`.

The refresh path also lacked an explicit UI-state file signature. The view model refreshed on timer and directory events, but did not track the `ui_state.json` file's modification/size signature as part of the UI revision signal.

## Fix

Implemented a UI-only presentation guard:

- Added `TaskLightProjectedPresentation` in `TaskLightCore`.
- `primaryStatus(from:)` uses the projected `global_status` as the main status and falls back to `lamp_status` only when needed.
- `displayTitle(from:)` derives the visible title from the projected primary status when `global_display_title` is stale or inconsistent.
- `TaskLightViewModel` now uses the projected presentation helper for `statusLabel`, compact title, visual status, and overall lamp status.
- `TaskLightViewModel` now tracks a refresh signature containing `ui_state.json` file mtime/size plus key projected state fields, and bumps `uiStateRevision` when that signature changes.

This does not change:

- State Projector status precedence
- Turn Runtime Arbiter scoring
- Hook Bridge semantics
- Stop -> done_unverified
- verify-only-green
- quota display-only boundary

## Regression Coverage

Added TaskLightChecks assertions:

- Fresh projected `RUNNING` read model still displays `RUNNING`.
- A mismatched projected state with `global_status=running`, `lamp_status=running`, and stale `global_display_title=DONE` displays `RUNNING`.
- The primary projected status remains `running` in that mismatch case.

## Verification

Commands run:

- `swift run --package-path mac/66TaskLight TaskLightChecks` -> pass
- `./script/check_ui_client.sh` -> pass
- `./script/check_all.sh` -> pass on rerun
- Focused post-`smoke_stop_priority_guard` segment -> pass

Observed live verification after rebuild:

- `build_and_run.sh --verify` completed inside `check_all`
- running app path: `/private/var/folders/vn/m0mvpbgn18q094vgnm2dgr6c0000gn/T/66tasklight-runtime/66TaskLight.app`
- `check_ui_client.sh` reported `STATUS=ok`
- State Projector reported `STATUS=ok`

## Residual Notes

- A first `check_all` attempt exited after `smoke_stop_priority_guard` without an emitted failure body. The same tail segment passed when run directly, and a full `check_all` rerun passed.
- Current live status can legitimately move from `running` to `pending` after this Codex turn emits stop/done_unverified signals. That is expected protocol behavior and is separate from the stale `Done` title bug.

## Outcome

The specific `Done`-while-projected-running UI mismatch is fixed at the LuckyCat presentation layer, with regression coverage preventing stale `global_display_title` from overriding projected status truth.
