# LuckyCat Edge Toggle Verification

Audit time: 2026-07-07 01:43 Asia/Shanghai

## Goal

- Remove the visible right-side chevron entry because it is visually intrusive.
- Keep the compact LuckyCat UI clean.
- Make edge collapse/restore depend on the real panel frame, not only the stored `edgeCollapsed` flag.
- Avoid the previous bug where one click produced an immediate collapse/restore loop.
- Do not change the status lamp algorithm, quota source, hooks, or projector semantics.

## Implementation Review

- Removed the visible `chevron.right` SwiftUI button from `TaskLightRootView`.
- Removed the native `TaskLightEdgeToggleOverlay` arrow layer from `TaskLightPanelController`.
- Added `compactPanelIsVisuallyEdgeCollapsed(_:)` so click handling uses the actual window size:
  - full cat: compact frame
  - right rail: edge rail frame
- Centralized edge toggling through `setEdgeCollapsedFromInteraction(_:source:)`.
- Added debounce and visual-state reconciliation:
  - prevents collapse followed by immediate restore in the same click burst
  - if model state and visible frame disagree, the controller reconciles the visible frame

## Evidence

- `swift build`: pass
- `./script/check_ui_client.sh`: `STATUS=ok`
- `./script/check_state_projector.sh`: `STATUS=ok`
- Source scan for `chevron.right`, `TaskLightEdgeToggleOverlay`, `nativeEdgeToggle`: absent
- Runtime binary scan for `chevron.right`, `nativeEdgeToggle`: absent
- Runtime trace confirms current version installs `mouseMonitor.installed`

## Bug Review

Previous behavior:

- Click events were captured, but one click could fire both collapse and restore paths.
- The visual result appeared as "no reaction".
- Internal `edgeCollapsed` state could disagree with the visible panel frame.
- The full cat could restore into the right-rail frame or right-rail origin, leaving the compact cat visibly clipped.

Current mitigation:

- The panel controller now checks actual window dimensions before deciding collapse vs restore.
- Duplicate click events within 0.30s are ignored.
- Same-state requests reconcile the visual frame instead of silently no-oping.
- Restoring from the right rail now computes a full compact frame from the current rail frame and clamps it to the visible screen.
- The right-rail frame is no longer allowed to overwrite the saved compact window frame.
- The visible right-side chevron affordance was removed.

## Final Verification Update

Verification rerun after the incomplete-restore regression:

- `swift build`: pass
- `./script/check_ui_client.sh`: `STATUS=ok`
- `./script/check_state_projector.sh`: `STATUS=ok`
- Source scan for `chevron.right`, `TaskLightEdgeToggleOverlay`, `nativeEdgeToggle`: absent
- Runtime binary scan for `chevron.right`, `nativeEdgeToggle`: absent
- Current on-screen 66TaskLight window bounds: `Width = 212`, `Height = 164`, `X = 1708`, `Y = 30`

The current window bounds match the full compact cat size rather than the right-rail size (`76 x 172`).

## Remaining Manual Acceptance

Manual check still required:

- Click the compact bottom status band.
- Expected: full LuckyCat collapses to the right vertical rail.
- Click the right vertical rail.
- Expected: LuckyCat restores to full compact view.

Automated mouse injection was attempted but not used as pass evidence because the system did not deliver injected pointer events to the app reliably in this environment.

## Audit Conclusion

No blocking issue was found by build, UI-client, state-projector, source, runtime binary, and current window-frame checks.

The fix is ready for user acceptance testing. Do not commit until the manual click path is confirmed on the visible desktop app.

## Atomic Toggle Fix Update

Audit time: 2026-07-07 02:02 Asia/Shanghai

### User-visible bug

- Clicking the bottom status orb could take about 20 seconds before the UI corrected itself.
- The intermediate state was wrong: the panel changed into a narrow right-side frame while still showing cropped full-cat content.
- The expected behavior is immediate: full cat -> vertical right rail, and right rail -> full cat, without a stale cropped state.

### Root cause

- Edge collapse had multiple writers:
  - SwiftUI view-layer gesture overlays called `viewModel.setEdgeCollapsed(...)` directly.
  - `TaskLightPanelController` also controlled the actual NSPanel frame.
- That split let content state and window frame state update out of order.
- Result: model said "edge rail", while the visible panel could still contain the full compact cat, or the reverse.

### Fix

- Removed direct edge-collapse writers from:
  - `LuckyCatCompactView`
  - `LuckyCatCompactShell`
  - `LuckyCatEdgeRailView`
- Removed legacy direct gesture layers:
  - `StatusOrbDoubleClickLayer`
  - `EdgeRailDoubleClickLayer`
- Centralized edge collapse/restore through `TaskLightPanelController`.
- Changed both collapse and restore frame changes to immediate frame application (`animated: false`).
- Narrowed the trigger hit area to the bottom status orb instead of a broad bottom/top band.
- Added transition traces for both directions:
  - `transition.edgeCollapsed.true.end.frame...`
  - `transition.edgeCollapsed.false.end.frame...`

### Regression self-test

- Added `script/smoke_luckycat_edge_toggle_atomic.sh`.
- The smoke verifies:
  - no SwiftUI view directly writes `edgeCollapsed`
  - old arrow/direct gesture layers are absent
  - status-orb hit testing exists
  - collapse and restore use immediate frame changes

### Verification

- `swift build`: pass
- `./script/check_ui_client.sh`: `STATUS=ok`
- `./script/check_state_projector.sh`: `STATUS=ok`
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: `STATUS=ok`
- Current running process: `TaskLightApp`
- Current on-screen 66TaskLight window bounds after relaunch: `Width = 76`, `Height = 172`, `X = 1836`, `Y = 40`
- Runtime trace showed an immediate collapse transition:
  - `transition.edgeCollapsed.true.begin.frame.212x164`
  - `transition.edgeCollapsed.true.end.frame.76x172`

### Manual acceptance status

- Automated click injection is not accepted as pass evidence in this environment because macOS rejected System Events click automation and CoreGraphics event posting did not reliably deliver clicks to the app.
- Manual check still required on the visible desktop:
  - click the bottom status orb from full cat
  - expected: immediate switch to the right vertical rail
  - click the right vertical rail
  - expected: immediate restore to full cat

### Current conclusion

- The known race that produced the cropped-cat edge state has been removed at source level.
- Automated checks pass.
- No remaining blocking issue was found by source audit, build, UI-client check, state-projector check, runtime bounds check, and the new regression smoke.
- Final visual acceptance still depends on the real desktop click path because OS-level synthetic clicks were not reliable in this environment.

## Capsule Click Reliability Update

Audit time: 2026-07-07 02:15 Asia/Shanghai

### New user-visible issue

- In capsule state, clicking the capsule could appear to do nothing.
- Previous restore could also leak into the compact cat tap handler after restore, opening the expanded dashboard instead of leaving the full compact cat visible.

### Revised interaction design

- Full cat -> capsule:
  - status orb has an AppKit click catcher (`StatusOrbClickCatcher`)
  - the catcher accepts first mouse
  - it sends a collapse request only
  - `TaskLightPanelController` performs the actual state change and window transition
- Capsule -> full cat:
  - rail has an AppKit click catcher (`EdgeRailClickCatcher`)
  - the catcher accepts first mouse
  - the click region is explicitly framed to `76 x 172`
  - it sends a restore request only
  - `TaskLightPanelController` performs the actual state change and window transition
- The compact tap handler is suppressed for a short window after collapse/restore so the same click cannot immediately open the expanded panel.
- Edge transitions currently use a fast `0.10s` AppKit alpha animation.

### Why this replaces the previous approach

- Global mouse monitors are not a reliable primary interaction path for this case.
- SwiftUI transparent gesture layers were not reliable enough for an inactive floating NSPanel.
- The new path uses a small AppKit bridge at the visible click target and keeps the state transition centralized in the panel controller.

### Verification

- `swift build`: pass
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: `STATUS=ok`
- `./script/check_ui_client.sh`: `STATUS=ok`
- `./script/check_state_projector.sh`: `STATUS=ok`
- Current running app after restart: `TaskLightApp`
- Current on-screen 66TaskLight window bounds after relaunch: `Width = 212`, `Height = 164`, `X = 1708`, `Y = 30`
- Regression smoke confirms:
  - no SwiftUI view directly writes `edgeCollapsed`
  - legacy direct gesture layers are absent
  - status orb click catcher exists
  - edge rail click catcher exists
  - collapse/restore request command channels exist
  - frame transition duration is `0.10s`

### Remaining manual acceptance

- Synthetic click delivery from this Codex process remains unreliable on this macOS session, so real desktop click acceptance is still the authority.
- Manual check:
  - click the bottom status orb: expected full cat -> vertical capsule in about 0.10s
  - click anywhere on the vertical capsule: expected capsule -> full cat in about 0.10s
  - after restore, the expanded dashboard should not open from the same click

## Dedicated Edge Panel Rebuild

Audit time: 2026-07-07 02:26 Asia/Shanghai

### Why the prior design was replaced

The previous implementation resized the compact LuckyCat NSPanel into the vertical capsule. This made the interaction fragile because the same window had to change content, frame, hit testing, and activation state at the same time.

The new design uses two dedicated panels:

- compact panel: full LuckyCat (`212 x 164`)
- edge panel: right-side vertical capsule (`76 x 172`)

Switching is now a panel visibility transition rather than a single panel morphing between two unrelated layouts.

### Implementation changes

- Added `TaskLightPanelDisplayMode.edgeRail`.
- Added a dedicated `edgePanel` in `TaskLightPanelController`.
- `showPanel()` now chooses between `frontCompactPanel` and `frontEdgePanel`.
- Full cat -> capsule:
  - status orb click sends a collapse request
  - controller shows `edgePanel`, hides `compactPanel`, and fades the edge panel in over `0.10s`
- Capsule -> full cat:
  - edge panel mouse interceptor catches click before SwiftUI
  - controller shows `compactPanel`, hides `edgePanel`, and fades compact panel in over `0.10s`
- Startup in capsule state now creates and fronts the dedicated `edgeRail` panel.

### Evidence

- `swift build`: pass
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: `STATUS=ok`
- `./script/check_ui_client.sh`: `STATUS=ok`
- `./script/check_state_projector.sh`: `STATUS=ok`
- Startup with `TaskLightEdgeCollapsed=true`:
  - one visible 66TaskLight window
  - bounds: `Width = 76`, `Height = 172`, `X = 1836`, `Y = 40`
  - trace includes `createPanel.edgeRail` and `showPanel.frontEdgePanel`
- Startup with `TaskLightEdgeCollapsed=false`:
  - one visible 66TaskLight window
  - bounds: `Width = 212`, `Height = 164`, `X = 1708`, `Y = 30`
  - trace includes `showPanel.frontCompactPanel`

### Remaining manual acceptance

Synthetic mouse events from the Codex process still do not reach the app in this macOS session; no panel trace is emitted after synthetic clicks. Therefore manual desktop click acceptance is still required:

- click full-cat status orb -> expect right capsule in about `0.10s`
- click right capsule -> expect full cat in about `0.10s`
- recovery should not open the expanded dashboard from the same click

## Edge Panel Hit Target Hardening

## Mouse Poll Fallback And Alpha Reliability Update

Audit time: 2026-07-07 09:30 Asia/Shanghai

### User-visible issue

- Real desktop clicks could still appear to do nothing in both full-cat and capsule states.
- Programmatic verification showed one concrete failure mode: the restore transition could execute while the restored compact panel stayed at `alpha = 0`, making it look like there was no response.
- Borderless floating panels also remained a risk for missed `mouseDown` delivery.

### Fix

- Added a 20ms mouse-button polling fallback in `TaskLightPanelController`.
  - It reads the real left-button state with `CGEventSource.buttonState`.
  - It checks `NSEvent.mouseLocation` against the current compact panel or edge panel frame.
  - If the click lands on the bottom status slot, it routes to the same collapse command.
  - If the click lands on the right capsule, it routes to the same restore command.
- Expanded the compact hit target from only the orb circle to the bottom status slot around the orb.
- Guarded stored compact frames:
  - compact-sized frame is accepted
  - edge-rail-sized frame is converted back to a full compact frame
  - invalid frame sizes are ignored with diagnostics
- Removed window alpha fade as the transition mechanism.
  - The compact panel and edge panel now explicitly set `alphaValue = 1` during switches.
  - This prevents restored-but-transparent windows.

### Verification

- `swift build`: pass
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: `STATUS=ok`
- `./script/smoke_luckycat_edge_toggle_runtime.sh`: `STATUS=ok`
- `./script/check_ui_client.sh`: `STATUS=ok`
- `./script/check_all.sh`: pass

Runtime edge-toggle self-test:

- `collapse_apply_ms=5.19`
- `restore_apply_ms=5.03`
- `collapsed_pass=True`
- `collapsed_alpha_pass=True`
- `restored_pass=True`
- `restored_alpha_pass=True`
- `compact_alpha=1`
- `edge_alpha=1`

Latest running app after restart:

- process: `TaskLightApp`
- visible window: full compact cat
- bounds: `Width = 212`, `Height = 164`, `X = 1690`, `Y = 48`
- alpha: `1`
- trace confirms:
  - `clickShield.compact.installed`
  - `clickShield.edgeRail.installed`
  - `mouseMonitor.installed`
  - `mousePoll.installed`
  - `showPanel.frontCompactPanel`

### Current conclusion

- The known no-response paths now have three layers of protection:
  - native click shield
  - panel mouse interceptor
  - 20ms real mouse-state polling fallback
- The transparent restore bug is fixed and covered by runtime smoke.
- Automated checks pass, including `check_all`.
- Final authority remains real desktop acceptance: click the bottom status ball/status slot to collapse, then click the right capsule to restore.

## First-Click MouseUp Fallback Update

Audit time: 2026-07-07 09:45 Asia/Shanghai

### Why another change was needed

- User-reported real desktop behavior still had no visible reaction from either full cat or capsule.
- macOS floating/borderless panels may use the first mouse-down to activate the app/window, so relying only on `mouseDown` is too weak.
- Synthetic AppleScript click testing was not accepted as proof because System Events did not target the custom floating panel reliably in this desktop session.

### Fix

- Expanded the window-level trigger path from mouse-down only to mouse-down and mouse-up:
  - `leftMouseDown`
  - `rightMouseDown`
  - `otherMouseDown`
  - `leftMouseUp`
  - `rightMouseUp`
  - `otherMouseUp`
- Added mouse-up handling to:
  - `TaskLightPanel.sendEvent`
  - `TaskLightPanel.mouseUp/rightMouseUp/otherMouseUp`
  - `TaskLightClickShieldView.mouseUp/rightMouseUp/otherMouseUp`
  - local/global event monitors
- Increased polling fallback from `20ms` to `8ms` to reduce short-click misses.

### Verification

- `swift build`: pass
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: `STATUS=ok`
- `./script/smoke_luckycat_edge_toggle_runtime.sh`: `STATUS=ok`
- `./script/check_ui_client.sh`: `STATUS=ok`
- `./script/check_all.sh`: pass

Runtime edge-toggle self-test after this change:

- `collapse_apply_ms=5.67`
- `restore_apply_ms=3.22`
- `collapsed_pass=True`
- `collapsed_alpha_pass=True`
- `restored_pass=True`
- `restored_alpha_pass=True`
- `compact_alpha=1`
- `edge_alpha=1`

Latest running app after restart:

- process: `TaskLightApp`
- visible window: full compact cat
- bounds: `Width = 212`, `Height = 164`, `X = 1690`, `Y = 48`
- alpha: `1`
- trace confirms:
  - `clickShield.compact.installed`
  - `clickShield.edgeRail.installed`
  - `mouseMonitor.installed`
  - `mousePoll.installed`

### Manual acceptance still required

- Click or double-click the bottom status ball/status slot.
- Expected: full compact cat switches to right vertical capsule immediately.
- Click or double-click the right vertical capsule.
- Expected: capsule switches back to full compact cat immediately.

## Full-Panel Hot Zone And Content Motion Update

Audit time: 2026-07-07 10:01 Asia/Shanghai

### Why this changed

- The previous versions still depended on a small status-ball/status-slot hit target.
- User feedback was broader: in full-cat and capsule states, clicking appeared to do nothing.
- To remove hit-target ambiguity, the complete full-cat compact window is now the collapse hot zone, and the complete right capsule remains the restore hot zone.

### Fix

- `taskLightCompactCollapseHit` now treats the whole compact panel frame as clickable for collapse.
- The compact native click shield, panel mouse interceptor, local/global monitors, and 8ms mouse poll fallback all route full-panel compact clicks to the same collapse path.
- The edge capsule still uses a full-frame restore hot zone.
- Added content-layer micro motion:
  - full cat enters with a 0.10s opacity/scale settle
  - edge rail enters with a 0.10s trailing-anchor scale/opacity settle
- Window switching remains immediate; no window alpha fade is used.

### Verification

- `swift build`: pass
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: `STATUS=ok`
- `./script/smoke_luckycat_edge_toggle_runtime.sh`: `STATUS=ok`
- `./script/check_ui_client.sh`: `STATUS=ok`
- `./script/check_all.sh`: pass

Runtime edge-toggle self-test after this change:

- `collapse_apply_ms=7.58`
- `restore_apply_ms=41.38`
- `collapsed_pass=True`
- `collapsed_alpha_pass=True`
- `restored_pass=True`
- `restored_alpha_pass=True`
- `compact_alpha=1`
- `edge_alpha=1`

Latest running app after restart:

- process: `TaskLightApp`
- visible window: full compact cat
- bounds: `Width = 212`, `Height = 164`, `X = 1690`, `Y = 49`
- alpha: `1`
- trace confirms:
  - `clickShield.compact.installed`
  - `clickShield.edgeRail.installed`
  - `mouseMonitor.installed`
  - `mousePoll.installed`

### Manual acceptance target

- In full-cat state, click anywhere on the small cat window.
- Expected: it switches to the right vertical capsule immediately with a subtle 0.10s content settle.
- In capsule state, click anywhere on the capsule.
- Expected: it switches back to the full cat immediately with a subtle 0.10s content settle.

## Dedicated Native Interaction Panel Update

Audit time: 2026-07-07 10:16 Asia/Shanghai

### Why this changed

- If the visible LuckyCat window is transparent/borderless, the system can still make real mouse delivery unreliable in some desktop states.
- The previous fixes hardened event handling inside the visual panels, but they still assumed the visual panel itself was selected as the click target.
- This update adds a separate AppKit-native interaction panel above the visual panel.

### Fix

- Added a dedicated `interactionPanel`.
- The interaction panel:
  - is a native `NSPanel`
  - has a tiny nonzero material hit surface
  - sits at `.statusBar` level above the visual floating panels
  - calls `makeKeyAndOrderFront(nil)` when synced
  - tracks the compact panel or edge rail frame
  - handles both mouse-down and mouse-up through the same centralized transition path
- In full-cat mode, the interaction panel covers the full compact cat (`212 x 164`).
- In edge mode, it covers the full vertical capsule (`76 x 172`).
- Expanded mode hides the interaction panel.

### Verification

- `swift build`: pass
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: `STATUS=ok`
- `./script/smoke_luckycat_edge_toggle_runtime.sh`: `STATUS=ok`
- `./script/check_ui_client.sh`: `STATUS=ok`
- `./script/check_all.sh`: pass

Runtime edge-toggle self-test:

- `collapse_apply_ms=5.18`
- `restore_apply_ms=4.61`
- `collapsed_pass=True`
- `collapsed_alpha_pass=True`
- `restored_pass=True`
- `restored_alpha_pass=True`

Latest running app after restart:

- process: `TaskLightApp`
- visual window: `Width = 212`, `Height = 164`, `X = 1690`, `Y = 49`, `Layer = 3`
- interaction window: `Width = 212`, `Height = 164`, `X = 1690`, `Y = 49`, `Layer = 25`
- trace confirms:
  - `panel.createdInteractionOnDemand`
  - `showPanel.compact.interactionPanel.front.frame.212x164`
  - `ensureVisibleOnActiveSpace.interactionPanel.front.frame.212x164`

### Manual acceptance target

- Click anywhere on the cat. The top interaction panel should receive the click and switch to the capsule.
- Click anywhere on the capsule. The same interaction panel should follow it and switch back to the cat.

Audit time: 2026-07-07 02:29 Asia/Shanghai

### External pattern reviewed

A GitHub API search for `SwiftUI FloatingPanel NSPanel` returned no direct repository results in this environment. I used the platform pattern from macOS NSPanel/FloatingPanel implementations instead:

- auxiliary floating UI should be an AppKit panel, not only a SwiftUI gesture layer
- edge/utility panels sometimes use non-activating panel style when they should not depend on app activation; this project later rejected that choice for the capsule because click reliability is more important here.
- visible rounded UI should not necessarily shrink the clickable hit area

### Additional hardening

- Superseded finding: the edge capsule panel briefly used `.nonactivatingPanel`, but the later warmup/click-reliability update removed it.
- The edge capsule panel no longer uses rounded-corner hit-test cropping.
- The visible capsule remains rounded, but the entire `76 x 172` panel rectangle is clickable.
- The edge panel still has a panel-level restore interceptor and a view-level AppKit click catcher.

### Verification

- `swift build`: pass
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: `STATUS=ok`
- `./script/check_ui_client.sh`: `STATUS=ok`
- Complete-cat startup:
  - one visible 66TaskLight window
  - bounds: `Width = 212`, `Height = 164`, `X = 1708`, `Y = 30`
- Forced capsule startup:
  - one visible 66TaskLight window
  - bounds: `Width = 76`, `Height = 172`, `X = 1836`, `Y = 40`
- Final runtime restored to complete-cat startup state:
  - one visible 66TaskLight window
  - bounds: `Width = 212`, `Height = 164`, `X = 1708`, `Y = 30`

## Dedicated Panel Warmup And Click Reliability Update

Audit time: 2026-07-07 02:51 Asia/Shanghai

### Findings

- The earlier implementation still allowed the compact SwiftUI root to swap into `LuckyCatEdgeRailView` when `edgeCollapsed=true`.
- That left two competing render paths:
  - compact panel content changing based on model state
  - dedicated edge panel handling the actual capsule window
- This made it possible for window size and view content to desynchronize, creating cropped-cat or delayed-capsule states.
- Synthetic mouse clicks from this Codex process still do not enter the app event stream, so real desktop click acceptance must be confirmed by the user.

### Fix

- `TaskLightRootView` compact mode now always renders the complete cat.
- The edge capsule is now rendered only by the dedicated `edgeRail` panel.
- `showPanel()` warms the dedicated edge panel at startup, frames it to the right edge, and keeps it hidden until needed.
- The edge panel no longer uses `.nonactivatingPanel`; it is now a regular clickable floating panel so real mouse events are less likely to be swallowed.
- The status orb hit area was widened to make status-ball clicks tolerant of small visual/layout offsets.
- Edge transition duration is now `0.10s`, keeping the visible reaction sub-200ms.

### Verification

- `swift build`: pass
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: `STATUS=ok`
- `./script/check_ui_client.sh`: `STATUS=ok`
- `./script/check_state_projector.sh`: `STATUS=ok`
- `./script/check_all.sh`: pass
- Smoke now checks:
  - compact root no longer swaps content based on `edgeCollapsed`
  - dedicated edge panel is warmed at startup
  - `.nonactivatingPanel` is absent from the edge-toggle panel path
  - edge transition duration is `0.10s`
- Complete-cat startup:
  - one visible 66TaskLight window
  - bounds: `Width = 212`, `Height = 164`, `X = 1708`, `Y = 30`
- Forced capsule startup:
  - one visible 66TaskLight window
  - bounds: `Width = 76`, `Height = 172`, `X = 1836`, `Y = 40`
- Final runtime restored to complete-cat startup state:
  - `TaskLightEdgeCollapsed=0`
  - one visible 66TaskLight window
  - bounds: `Width = 212`, `Height = 164`, `X = 1708`, `Y = 30`

### Acceptance Status

- Code-side, startup, size, and smoke coverage: pass.
- Real click acceptance: not proven by automation in this Codex session because macOS rejected or ignored synthetic click delivery to the floating panel.
- Required manual check:
  - click the status orb once: complete cat should become vertical capsule immediately with about `0.10s` animation
  - click the capsule once: capsule should restore to the complete cat immediately with about `0.10s` animation

## Runtime Self-Test Coverage Update

Audit time: 2026-07-07 03:03 Asia/Shanghai

### Change

- Added an internal app launch argument: `--tasklight-edge-self-test`.
- Added `TaskLightPanelController.runEdgeToggleSelfTest(...)`.
- Added `./script/smoke_luckycat_edge_toggle_runtime.sh`.
- Added both LuckyCat edge-toggle smoke checks to `./script/check_all.sh`.
- The runtime self-test launches the app, runs controller-level collapse and restore, verifies window visibility and frame sizes, writes `~/.66tasklight/edge_toggle_self_test.json`, then exits.

### Runtime Evidence

- `./script/smoke_luckycat_edge_toggle_runtime.sh`: `STATUS=ok`
- `./script/check_all.sh`: pass
- Runtime self-test result:
  - `edge_toggle_self_test_status=ok`
  - `collapse_apply_ms=32.62`
  - `restore_apply_ms=33.86`
  - `transition_duration_ms=100`
  - `collapsed_pass=True`
  - `restored_pass=True`
  - capsule frame: `76 x 172`
  - compact frame: `212 x 164`
- Final normal app state after `check_all`:
  - `TaskLightEdgeCollapsed=0`
  - visible 66TaskLight window: `212 x 164`

### Remaining Evidence Gap

- A system-level synthetic click was attempted against the visible status orb using the current real window frame.
- Result: macOS did not deliver that synthetic click into the app event stream; the window stayed `212 x 164` and no panel-controller click trace was produced.
- Therefore, automated evidence now proves:
  - controller switching path is sub-50ms
  - visual transition duration is 100ms
  - compact and capsule window sizes are correct
  - `check_all` includes this regression
- Automated evidence still does not prove real human mouse event delivery. Final acceptance still requires one manual click test on the live desktop.

## Native Click Shield And Repeat-Restore Guard

Audit time: 2026-07-07 08:58 Asia/Shanghai

### Finding From Live Trace

- The live trace showed real capsule clicks can enter `edgePanelMouse.restore`.
- The same click burst could trigger restore repeatedly in the same second.
- Repeated restore calls reset the compact panel transition over and over, making the user-visible restore feel like it did nothing or was unstable.

### Fix

- Added `TaskLightClickShieldView`, a native AppKit hit layer.
- Compact mode now has a native status-orb hit shield:
  - `nativeClickShield.statusOrbCollapse`
  - it only catches the bottom status orb region
  - normal compact body taps still pass through to the existing expanded-panel behavior
- Edge capsule now has a full native AppKit hit shield:
  - `nativeClickShield.edgeRestore`
  - it covers the entire `76 x 172` capsule window
- Added repeat-click protection:
  - `edgeTransitionLockedUntil`
  - `ignoredAlreadyRestored`
  - local/global mouse monitors now listen to left, right, and other mouse-down events
- Edge panel now also sets `worksWhenModal=true`.

### Verification

- `swift build`: pass
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: `STATUS=ok`
- `./script/smoke_luckycat_edge_toggle_runtime.sh`: `STATUS=ok`
- `./script/check_ui_client.sh`: `STATUS=ok`
- `./script/check_all.sh`: pass
- Runtime self-test after native click shield:
  - `edge_toggle_self_test_status=ok`
  - `collapse_apply_ms=3.99`
  - `restore_apply_ms=5.57`
  - `transition_duration_ms=100`
  - `collapsed_pass=True`
  - `restored_pass=True`
  - capsule frame: `76 x 172`
  - compact frame: `212 x 164`
- Final normal app state:
  - `TaskLightEdgeCollapsed=0`
  - visible 66TaskLight window: `212 x 164`

### Manual Acceptance Required

- The automated controller/runtime path is now covered by `check_all`.
- Real desktop click delivery still must be verified by the user:
  - click bottom status orb once: full cat should become right-side vertical capsule immediately
  - click any visible part of the capsule once: capsule should restore to full cat immediately
  - repeated clicks should not cause the restored cat to flicker or stay hidden

### Remaining manual acceptance

Manual click remains the only missing proof because synthetic clicks still do not reach the app event stream from this Codex session. The expected real interaction is unchanged:

- click status orb -> capsule in about `0.10s`
- click any visible part of capsule -> full cat in about `0.10s`

## Edge Restore Force Path Update

Audit time: 2026-07-07 02:34 Asia/Shanghai

### New hardening

- Edge capsule restore now bypasses normal edge-toggle debounce.
- All capsule restore sources route to `forceRestoreFromEdgePanel(...)`:
  - edge panel mouse interceptor
  - local/global mouse monitor over edge panel bounds
  - edge rail AppKit click catcher request channel
- `TaskLightPanel.sendEvent(_:)` now routes left, right, and other mouse-down events through the panel interceptor.
- This prevents a fast click or repeated click from being ignored because the previous collapse wrote `lastEdgeToggleAt`.

### Verification

- `swift build`: pass
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: `STATUS=ok`
- `./script/check_ui_client.sh`: `STATUS=ok`
- `./script/check_state_projector.sh`: `STATUS=ok`
- Smoke now checks:
  - `forceRestoreFromEdgePanel` exists
  - panel intercepts all mouse-down button types through `isTaskLightMouseDown`
  - dedicated edge panel exists
  - edge panel restore path exists; later smoke explicitly verifies `.nonactivatingPanel` is absent
  - edge panel uses rectangular hit target instead of rounded hit-test clipping
- Final runtime state:
  - one visible 66TaskLight window
  - bounds: `Width = 212`, `Height = 164`, `X = 1708`, `Y = 30`

### Remaining manual acceptance

Manual desktop click is still the only missing proof because synthetic click events from this Codex process still do not enter the app event stream.

## Panel Responder Fallback Update

Audit time: 2026-07-07 02:37 Asia/Shanghai

### New hardening

- `TaskLightPanel` now intercepts mouse down events in two layers:
  - `sendEvent(_:)`
  - responder fallbacks: `mouseDown`, `rightMouseDown`, `otherMouseDown`
- This means edge panel restore no longer depends only on AppKit window event dispatch reaching `sendEvent` before content view routing.
- The smoke test now asserts these responder fallbacks exist.

### Verification

- `swift build`: pass
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: `STATUS=ok`
- `./script/check_ui_client.sh`: `STATUS=ok`
- Complete-cat startup:
  - one visible 66TaskLight window
  - bounds: `Width = 212`, `Height = 164`, `X = 1708`, `Y = 30`
- Forced capsule startup:
  - one visible 66TaskLight window
  - bounds: `Width = 76`, `Height = 172`, `X = 1836`, `Y = 40`
- Final runtime restored to complete-cat startup state:
  - one visible 66TaskLight window
  - bounds: `Width = 212`, `Height = 164`, `X = 1708`, `Y = 30`
