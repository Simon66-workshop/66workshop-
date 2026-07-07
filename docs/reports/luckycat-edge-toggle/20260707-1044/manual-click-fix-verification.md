# LuckyCat Edge Toggle Manual-Click Fix Verification

Generated at: 2026-07-07 10:44 Asia/Shanghai

## Scope

This verification covers the LuckyCat compact-to-edge toggle interaction only.
It does not change or re-audit the status lamp algorithm, quota data source,
Hook Bridge, State Projector, Turn Runtime Arbiter, or workspace hook semantics.

## Root Cause

The previous edge-toggle implementation used too many input paths at once:

- a separate invisible interaction panel;
- local/global mouse monitors;
- an 8ms mouse polling fallback;
- mouse-down and mouse-up handlers both able to trigger edge actions.

Runtime trace showed one click could be consumed repeatedly as both collapse and
restore attempts. The transition lock then ignored the repeated restore events,
which made the visible behavior feel delayed or unresponsive in manual testing.

## Fix Summary

- Removed the invisible interaction panel from the normal click path.
- Removed global/local mouse monitors and mouse polling for edge toggle.
- Stopped treating mouse-up as a toggle trigger.
- Centralized compact status-orb handling in `handleCompactPanelMouseDown`.
- Centralized edge-rail restore handling in `handleEdgeRailMouseDown`.
- Corrected the compact click shield so it only hits the status orb area.
- Added safe click diagnostics at `~/.66tasklight/luckycat_click_diagnostics.json`.
- Made click diagnostics asynchronous so file IO cannot block the interaction.
- Updated runtime self-test to prove the same click-handler path, not only a
  direct model-state write.

## Verification Results

| Check | Result | Evidence |
|---|---:|---|
| Swift build | PASS | `swift build` completed |
| UI client check | PASS | `./script/check_ui_client.sh` returned `STATUS=ok` |
| Atomic edge toggle smoke | PASS | `./script/smoke_luckycat_edge_toggle_atomic.sh` returned `STATUS=ok` |
| Runtime edge toggle smoke | PASS | `./script/smoke_luckycat_edge_toggle_runtime.sh` returned `STATUS=ok` |
| Full check suite | PASS | `./script/check_all.sh` completed successfully |

Runtime self-test latest observed values:

- `click_path_collapsed=True`
- `collapse_apply_ms=33.34512503352016`
- `restore_apply_ms=4.966625012457371`
- `transition_duration_ms=100`
- `collapsed_pass=True`
- `restored_pass=True`

## Safety Boundary

- No status lamp aggregation rule was changed.
- No quota main-lamp behavior was changed.
- No Hook Bridge or State Projector semantics were changed.
- No hooks were installed or trusted.
- No commit or push was performed.

## Manual Acceptance Note

Automated checks now cover the click-handler path and pass. Final acceptance
still requires one human UI check on the live desktop app:

1. Click or double-click the compact status orb.
2. The full cat should switch to the right vertical capsule immediately.
3. Click the right vertical capsule.
4. The full cat should restore immediately.
5. If either action fails, inspect `~/.66tasklight/luckycat_click_diagnostics.json`
   to distinguish "click not delivered" from "click delivered but ignored".
