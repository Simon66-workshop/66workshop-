# LuckyCat Free Floating Capsule

## Change

The collapsed capsule is no longer locked to the right screen edge after the
user drags it.

Initial collapse still places the capsule near the right side as a sensible
default, but once dragged it behaves as a free floating compact window:

- Dragging the capsule updates both x and y.
- Drag end does not snap the capsule back to the right edge.
- The capsule frame is stored separately from the full cat frame.
- Reopening/collapsing can reuse the stored capsule frame when it is still
  visible on the current screen.
- If screen geometry changes, the stored capsule frame is clamped back into the
  visible area.

## Files

- `mac/66TaskLight/Sources/TaskLightApp/TaskLightPanelController.swift`
- `mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift`
- `script/smoke_luckycat_edge_toggle_atomic.sh`
- `docs/reports/luckycat-edge-toggle/20260707-1435/video-review-click-drag-fix.md`

## Verification

- `swift build`: pass
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: pass
  - `edge_free_drag=present`
- `./script/smoke_luckycat_edge_toggle_runtime.sh`: pass
  - `edge_drag_pass=True`
  - runtime edge frame moved to `x=940, y=471` in the latest full check, proving
    it is not constrained to the right edge.
- `./script/check_ui_client.sh`: pass
- `./script/check_all.sh`: pass

## Manual Retest

- Collapse to capsule.
- Drag the capsule left/right/up/down.
- It should stay wherever you drop it, without snapping to the right edge.
- Click the capsule to restore full cat.
- Collapse again; it should prefer the stored capsule position if still visible.
