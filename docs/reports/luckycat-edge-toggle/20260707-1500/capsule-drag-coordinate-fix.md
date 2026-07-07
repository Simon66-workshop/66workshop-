# LuckyCat Capsule Drag Coordinate Fix

## Problem

After enabling free capsule placement, manual dragging could feel unstable or
drift unexpectedly.

## Root Cause

The drag loop reused `normalizedPanelScreenPoint(...)`, which is intended for
click fallback paths that may receive mixed coordinate systems. During a live
drag, the panel frame changes continuously, so coordinate normalization can
change interpretation mid-gesture and produce unstable deltas.

## Fix

- Added a dedicated `currentDragScreenPoint()` path for drag gestures.
- `trackPanelPress(...)` now uses stable `NSEvent.mouseLocation` screen
  coordinates for drag start/current points.
- Mouse-button polling fallback uses the same stable drag coordinate source.
- `normalizedPanelScreenPoint(...)` remains available for click/event fallback
  diagnostics, but it is no longer used inside the primary drag tracker.
- Static smoke now rejects normalized coordinates inside `trackPanelPress(...)`.

## Verification

- `swift build`: pass
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: pass
  - `edge_free_drag=present`
  - drag path uses stable screen coordinates
- `./script/smoke_luckycat_edge_toggle_runtime.sh`: pass
  - `edge_drag_pass=True`
  - `compact_drag_pass=True`
- `./script/check_ui_client.sh`: pass
- `./script/check_all.sh`: pass

## Manual Retest

- Collapse to capsule.
- Drag capsule slowly and quickly in all directions.
- The capsule should track the pointer without jumping or snapping.
- Release should leave the capsule exactly where it was dropped.
