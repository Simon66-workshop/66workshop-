# LuckyCat Edge Toggle Interaction Fix Retrospective

Generated at: 2026-07-07 11:49 CST

## User-Visible Issue

- Full LuckyCat mode: clicking the bottom/status orb sometimes took 10-20 seconds before switching to the right rail.
- Right rail mode: clicking the rail sometimes did not restore the full cat.
- A startup/activation path could also make the cat collapse unexpectedly when the cursor was already over the cat.

## Root Causes

1. Compact collapse still depended on double-click/timing paths in some fallback routes.
2. Edge restore was blocked by the short transition lock, so repeated clicks during/after transition could be ignored.
3. The CGEvent/NSEvent fallback compared top-origin mouse coordinates against AppKit bottom-origin window frames.
4. `handleAlertPlayback()` used repeated array `contains` checks over the played event ledger, which could block the main thread when many events existed.
5. Activation fallback was too broad and could collapse the cat during launch/focus recovery without a real mouse button press.

## Changes

- Compact panel click now collapses directly; no delayed double-click recognition is required.
- Edge rail click now restores through a force-restore path that bypasses the short transition lock.
- Added screen-coordinate normalization for event-tap and mouse-poll fallback paths.
- Kept activation fallback, but only when a mouse button is actively pressed.
- Optimized alert playback ledger lookup by using a `Set` while preserving existing ledger semantics.
- Updated `smoke_luckycat_edge_toggle_atomic.sh` to guard against delayed double-click logic and require coordinate normalization.

## Verification

- `swift build`: passed.
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: passed.
- `./script/smoke_luckycat_edge_toggle_runtime.sh`: passed.
  - collapse: 2.96 ms in the final `check_all` run
  - restore: 5.40 ms in the final `check_all` run
- `./script/check_ui_client.sh`: passed.
- `./script/check_all.sh`: passed.

## Current State

- Latest app bundle rebuilt and relaunched.
- Runtime window check after final verification: full compact cat visible.
- Status algorithm, quota source, Hook Bridge, State Projector, and Turn Runtime Arbiter semantics were not changed.

## Manual Acceptance Needed

- Click the full cat bottom/status area: it should collapse to the vertical right rail immediately.
- Click the right rail: it should restore the full cat immediately.
