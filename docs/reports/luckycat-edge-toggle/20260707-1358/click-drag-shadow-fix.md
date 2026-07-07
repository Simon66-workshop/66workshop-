# LuckyCat Click/Drag And Edge Shadow Fix

Generated at: 2026-07-07 13:58 CST

## Issue

- Single click could toggle between full cat and right rail, but long-press drag was also interpreted as a click.
- Right rail could not be dragged reliably.
- The right rail had a visible rectangular corner shadow around the rounded capsule.

## Fix

- Added a click/drag split with a small movement threshold.
- Native panel events now track press, drag, and release:
  - no meaningful movement: toggle full cat / right rail
  - movement past threshold: move the panel and do not toggle
- Mouse polling fallback now uses the same press lifecycle and clears stale fallback presses when the native panel tracker takes over.
- Right rail drag keeps the rail in rail mode and updates its vertical position.
- Removed the right rail outer shadow and clipped the rail to the rounded capsule shape.

## Verification

- `swift build`: passed.
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: passed.
- `./script/smoke_luckycat_edge_toggle_runtime.sh`: passed.
  - `compact_drag_pass=True`
  - `edge_drag_pass=True`
  - `click_path_collapsed=True`
  - `restored_pass=True`
- `./script/check_ui_client.sh`: passed.
- `./script/check_all.sh`: passed.

## Notes

- Status lamp semantics, quota source, Hook Bridge, State Projector, and Turn Runtime Arbiter logic were not changed.
- Right rail dragging is intentionally constrained vertically so it stays as a right-side rail rather than becoming a free-floating widget.
