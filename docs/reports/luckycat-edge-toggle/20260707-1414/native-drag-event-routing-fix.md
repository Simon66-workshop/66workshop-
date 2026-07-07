# LuckyCat Edge Toggle Native Drag Event Routing Fix

## Scope

This fix is limited to the LuckyCat compact/collapsed window interaction layer.
It does not change the status lamp algorithm, quota data source, Hook Bridge,
State Projector, or Turn Runtime Arbiter semantics.

## User-Visible Bug

- The edge capsule could not be dragged reliably.
- Dragging the full cat could stutter, then jump back or switch to the edge
  capsule.
- The edge capsule had previously shown square-looking corner shadow artifacts.

## Root Cause

Two input paths were competing with the native panel mouse handling:

1. SwiftUI/AppKit click catcher overlays inside the compact status orb and edge
   rail handled `mouseDown` immediately.
2. The app activation fallback also toggled or restored on `mouseDown`, before
   it knew whether the user intended a click or a drag.

That meant a long press or drag could be interpreted as a short click, so the
window changed modes while the user was trying to move it.

## Fix

- Removed the internal compact status-orb click catcher.
- Removed the internal edge-rail click catcher.
- Kept click and drag routing at the panel/window layer.
- Used native `NSWindow.performDrag(with:)` for smooth manual dragging.
- Changed the activation fallback to diagnostic-only observation; it no longer
  toggles or restores before drag intent is known.
- Kept edge rail drag constrained to the right edge while preserving the user's
  vertical placement.
- Kept the rectangular edge shadow removed.

## Verification

- `swift build`: pass
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: pass
- `./script/smoke_luckycat_edge_toggle_runtime.sh`: pass
  - `compact_drag_pass=True`
  - `edge_drag_pass=True`
  - `click_path_collapsed=True`
  - `restored_pass=True`
  - collapse measured at ~2.7 ms in the latest run
  - restore measured at ~7.0 ms in the latest run
- `./script/check_ui_client.sh`: pass
- `./script/check_all.sh`: pass

## Manual Acceptance Checklist

- Short click on full cat: switches to right edge capsule.
- Long press and drag on full cat: moves the cat and does not switch mode.
- Short click on edge capsule: restores full cat.
- Long press and drag on edge capsule: moves the capsule vertically on the right
  edge and does not restore.
- Edge capsule has no square corner shadow.

## Residual Note

The runtime self-test proves the panel state and transition paths, but final
drag feel still depends on manual desktop verification because macOS may not
deliver synthetic mouse events from automation into this floating panel in every
local session.
