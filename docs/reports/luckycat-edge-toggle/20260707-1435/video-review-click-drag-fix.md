# LuckyCat Edge Toggle Video Review Fix

## Input Evidence

- Manual review video: `/Users/macmini-simon66/Downloads/IMG_2207.MOV`
- Duration: 18.55 seconds
- Observed issue: the full cat switched to the edge rail too easily during
  attempted drag. The edge rail also occupied more horizontal content area than
  desired.

## Root Cause

The compact cat treated a short click anywhere on the cat panel as a collapse
request. That made normal press-and-drag attempts feel like the cat switched
immediately, especially when the first motion was small or the user pressed on
the cat body instead of the bottom status orb.

## Behavior Change

- Compact cat body click no longer collapses to the rail.
- Only the bottom status orb / bottom status slot can collapse the cat.
- Long press does not toggle.
- Drag movement over the threshold moves the current window and does not toggle.
- Edge rail is a free-floating capsule after the user drags it; initial collapse
  still starts near the right side.
- Edge rail width was reduced from `76` to `64`, and height from `172` to `158`,
  making it less intrusive over document content.

## Verification

- `swift build`: pass
- `./script/smoke_luckycat_edge_toggle_atomic.sh`: pass
- `./script/smoke_luckycat_edge_toggle_runtime.sh`: pass
  - `compact_drag_pass=True`
  - `body_click_pass=True`
  - `click_path_collapsed=True`
  - `edge_drag_pass=True`
  - `restored_pass=True`
- `./script/check_ui_client.sh`: pass
- `./script/check_all.sh`: pass

## Manual Retest Checklist

- Drag from cat face/body: cat should move, not switch to rail.
- Click cat face/body without dragging: cat should stay as full cat.
- Short click bottom status orb: cat should switch to right rail.
- Long press bottom status orb: should not switch unless released as a short click.
- Drag edge rail: rail should move freely and keep that capsule position.
- Short click edge rail: full cat should restore.
