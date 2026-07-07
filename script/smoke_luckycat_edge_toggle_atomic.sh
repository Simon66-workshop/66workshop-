#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp"

fail() {
  echo "STATUS=fail"
  echo "reason=$1"
  exit 1
}

controller="$APP_DIR/TaskLightPanelController.swift"
rail_view="$APP_DIR/Screens/LuckyCatEdgeRailView.swift"
compact_shell="$APP_DIR/Components/LuckyCatCompactShell.swift"
view_model="$APP_DIR/TaskLightViewModel.swift"

if rg -n "viewModel\\.setEdgeCollapsed\\(" \
  "$APP_DIR/Screens/LuckyCatCompactView.swift" \
  "$APP_DIR/Screens/LuckyCatEdgeRailView.swift" \
  "$APP_DIR/Components/LuckyCatCompactShell.swift" \
  "$APP_DIR/TaskLightRootView.swift" >/tmp/66tasklight-edge-toggle-direct-writes.txt; then
  cat /tmp/66tasklight-edge-toggle-direct-writes.txt
  fail "edgeCollapsed is still written directly from SwiftUI views"
fi

if rg -n "StatusOrbDoubleClick|EdgeRailDoubleClick|chevron\\.right|TaskLightEdgeToggleOverlay|nativeEdgeToggle|onStatusOrbDoubleTap" "$APP_DIR" >/tmp/66tasklight-edge-toggle-legacy.txt; then
  cat /tmp/66tasklight-edge-toggle-legacy.txt
  fail "legacy edge toggle affordance or direct gesture layer is still present"
fi

if rg -n "interactionPanel|ensureInteractionPanel|syncInteractionPanel|handleInteractionPanelClick" "$controller" >/tmp/66tasklight-edge-toggle-interaction-panel.txt; then
  cat /tmp/66tasklight-edge-toggle-interaction-panel.txt
  fail "edge toggle should not use a separate invisible interaction panel"
fi

if rg -n "NSEvent\\.addGlobalMonitor|NSEvent\\.addLocalMonitor|withTimeInterval: 0\\.008" "$controller" >/tmp/66tasklight-edge-toggle-global-input.txt; then
  cat /tmp/66tasklight-edge-toggle-global-input.txt
  fail "edge toggle should not use NSEvent global/local monitors or 8ms polling"
fi

if rg -n "override func mouseUp|override func rightMouseUp|override func otherMouseUp" "$controller" >/tmp/66tasklight-edge-toggle-mouseup.txt; then
  cat /tmp/66tasklight-edge-toggle-mouseup.txt
  fail "mouse-up must not be a toggle trigger"
fi

rg -q "isTaskLightMouseDown" "$controller" \
  || fail "panel should intercept only mouse-down trigger types"

rg -q "handleCompactPanelMouseDown" "$controller" \
  || fail "central compact click handler is missing"

rg -q "handleEdgeRailMouseDown" "$controller" \
  || fail "central edge rail click handler is missing"

rg -q "taskLightCompactStatusOrbHit" "$controller" \
  || fail "status orb hit test is missing"

rg -q "compactStatusOrbCenter" "$controller" \
  || fail "status orb self-test point is missing"

rg -Fq "shield.hitMode = .full" "$controller" \
  || fail "compact click shield must cover the full cat for reliable manual collapse"

rg -q "panel_click_no_toggle" "$controller" \
  || fail "compact body click should stay compact"

if rg -n "collapse_panel_click" "$controller" >/tmp/66tasklight-edge-toggle-full-cat-collapse.txt; then
  cat /tmp/66tasklight-edge-toggle-full-cat-collapse.txt
  fail "full compact-panel click must not collapse the cat"
fi

if rg -n "inside_compact_wait_second_click|collapse_double_click|taskLightCompactDoubleClick" "$controller" >/tmp/66tasklight-edge-toggle-double-click.txt; then
  cat /tmp/66tasklight-edge-toggle-double-click.txt
  fail "compact collapse should not wait for double-click recognition"
fi

if rg -n "scheduleCompactSingleClick|single_click_expand|pendingCompactSingleClick" "$controller" >/tmp/66tasklight-edge-toggle-delayed-click.txt; then
  cat /tmp/66tasklight-edge-toggle-delayed-click.txt
  fail "edge toggle should not use delayed single-click expand scheduling"
fi

rg -q "handleActivationClickIfInsidePanel" "$controller" "$APP_DIR/TaskLightAppDelegate.swift" \
  || fail "activation-click fallback is missing"

rg -q "observed_status_orb_mouse_down" "$controller" \
  || fail "activation fallback should only observe compact mouse-down, not toggle"

rg -q "observed_mouse_down" "$controller" \
  || fail "activation fallback should only observe edge mouse-down, not restore"

if rg -n "activation\\..*panelCollapse|activation\\..*edgeRestore|activation\\..*setEdgeCollapsed|activation\\..*handleEdgeRailMouseDown" "$controller" >/tmp/66tasklight-edge-toggle-activation-toggle.txt; then
  cat /tmp/66tasklight-edge-toggle-activation-toggle.txt
  fail "activation fallback must not toggle or restore before drag intent is known"
fi

rg -q "installMouseEventTap" "$controller" \
  || fail "mouse event tap fallback is missing"

rg -q "CGEvent\\.tapCreate" "$controller" \
  || fail "CGEvent tap creation is missing"

rg -q "eventTap.any.observed" "$controller" \
  || fail "event tap diagnostic path is missing"

rg -q "startMouseButtonPollingFallback" "$controller" \
  || fail "controlled mouse button polling fallback is missing"

rg -q "CGEventSource\\.buttonState" "$controller" \
  || fail "controlled mouse button edge polling is missing"

rg -q "Timer\\(timeInterval: 0\\.016" "$controller" \
  || fail "mouse polling fallback should use 16ms cadence"

rg -q "handleMouseCoordinateInput" "$controller" \
  || fail "shared coordinate click handler is missing"

rg -q "trackPanelPress" "$controller" \
  || fail "panel press tracker is missing"

rg -q "taskLightClickMaxDuration" "$controller" \
  || fail "short-click duration gate is missing"

rg -q "taskLightDragThreshold" "$controller" \
  || fail "click/drag threshold is missing"

rg -q "edgeRailWindowFrame" "$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift" "$controller" \
  || fail "free capsule frame persistence is missing"

rg -q "saveEdgeRailFrame" "$controller" \
  || fail "edge rail drag should persist its free position"

rg -q "rememberEdgeRailFrame" "$controller" \
  || fail "edge rail should remember its latest moved position"

rg -q "currentEdgeRailFrame" "$controller" \
  || fail "restore should use the latest edge rail frame as its anchor"

rg -q "restored_from_moved_edge_pass" "$controller" "$ROOT_DIR/script/smoke_luckycat_edge_toggle_runtime.sh" \
  || fail "runtime self-test should prove restore anchors to the moved capsule"

rg -q "edgeRailFramePersistWorkItem" "$controller" \
  || fail "edge rail movement should debounce persisted frame writes"

rg -q "persistImmediately: false" "$controller" \
  || fail "edge rail window move should not synchronously persist every frame"

rg -q "shouldRasterize = true" "$controller" \
  || fail "edge rail hosting layer should be rasterized for smoother dragging"

rg -q "transaction.animation = nil" "$rail_view" \
  || fail "edge rail should disable implicit SwiftUI animations"

if rg -n "snapEdgePanelToRightEdge|snapRightEdge" "$controller" >/tmp/66tasklight-edge-toggle-snap.txt; then
  cat /tmp/66tasklight-edge-toggle-snap.txt
  fail "edge rail drag must not snap back to the right edge"
fi

rg -Fq "nextEvent(" "$controller" \
  || fail "panel press should track dragged/up events before toggling"

rg -q "leftMouseDragged" "$controller" \
  || fail "panel press should handle mouse-dragged events"

rg -Fq "screenPoint(for: event, in: panel)" "$controller" \
  || fail "panel drag path should derive the start screen point from the mouse-down event"

rg -Fq "screenPoint(for: next, in: panel)" "$controller" \
  || fail "panel drag path should derive screen points from each panel event"

rg -q "applyDraggedFrame" "$controller" \
  || fail "panel drag should apply a non-accumulating frame delta"

rg -q "setFrameOrigin" "$controller" \
  || fail "panel drag should move same-size windows by origin without forcing redraw"

rg -q "performDrag\\(with: event\\)" "$controller" \
  || fail "edge rail drag should hand off to native AppKit window dragging"

python3 - "$controller" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
start = source.index("private func trackPanelPress")
end = source.index("func handleMouseEventTap", start)
body = source[start:end]
if "normalizedPanelScreenPoint" in body:
    print("trackPanelPress still normalizes drag coordinates")
    raise SystemExit(1)
if "currentDragScreenPoint()" in body:
    print("trackPanelPress still uses global mouse location for panel drag")
    raise SystemExit(1)
if "movePanel(panel, target: target, from:" in body:
    print("trackPanelPress still uses incremental drag deltas")
    raise SystemExit(1)
if "startFrame = panel.frame" not in body:
    print("trackPanelPress does not anchor dragging to the mouse-down frame")
    raise SystemExit(1)
if "target == .edgeRail" not in body or "performDrag(with: event)" not in body:
    print("trackPanelPress does not use native drag for the edge rail")
    raise SystemExit(1)
PY

if rg -n "entranceVisible|withAnimation|scaleEffect" "$rail_view" >/tmp/66tasklight-edge-toggle-rail-animation.txt; then
  cat /tmp/66tasklight-edge-toggle-rail-animation.txt
  fail "edge rail should not run entrance scale animations that can stutter dragging"
fi

if rg -n "pulsing: status == \\.running|pulsing: true" "$rail_view" >/tmp/66tasklight-edge-toggle-rail-pulse.txt; then
  cat /tmp/66tasklight-edge-toggle-rail-pulse.txt
  fail "edge rail should not run continuous orb pulse while draggable"
fi

rg -q "press_hold_no_toggle" "$controller" \
  || fail "long press should not toggle edge state"

rg -q "beginFallbackPress" "$controller" \
  || fail "mouse polling fallback should begin a press instead of toggling immediately"

rg -q "finishFallbackPress" "$controller" \
  || fail "mouse polling fallback should finish a press before toggling"

rg -q "drag_end" "$controller" \
  || fail "drag completion diagnostic is missing"

rg -q "normalizedPanelScreenPoint" "$controller" \
  || fail "coordinate fallback should normalize CGEvent/NSEvent screen coordinates"

if rg -n 'handleMouseCoordinateInput\(source: "eventTap"|handleMouseCoordinateInput\(source: "mousePoll"' "$controller" >/tmp/66tasklight-edge-toggle-immediate-fallback.txt; then
  cat /tmp/66tasklight-edge-toggle-immediate-fallback.txt
  fail "fallback mouse-down paths must not toggle before drag intent is known"
fi

rg -Fq "panelMouse.compact" "$controller" \
  || fail "panel mouse compact click path is missing"

rg -Fq "nativeClickShield.compact" "$controller" \
  || fail "native compact status-orb click shield path is missing"

rg -Fq "nativeClickShield.edgeRail" "$controller" \
  || fail "native edge restore click shield path is missing"

rg -q "writeClickDiagnostic" "$controller" \
  || fail "click diagnostics snapshot is missing"

rg -q "luckycat_click_diagnostics\\.json" "$controller" \
  || fail "click diagnostics file target is missing"

rg -q "body_click_pass" "$controller" \
  || fail "runtime self-test should prove compact body click stays compact"

rg -q "click_path_collapsed" "$controller" \
  || fail "runtime self-test should prove the click handler path"

rg -q "transition\\.edgeCollapsed\\.true\\.end\\.frame" "$controller" \
  || fail "collapse transition trace is missing"

rg -q "transition\\.edgeCollapsed\\.false\\.end\\.frame" "$controller" \
  || fail "restore transition trace is missing"

if rg -n "StatusOrbClickCatcher|requestEdgeCollapseFromStatusOrb" "$compact_shell" "$APP_DIR/Screens/LuckyCatCompactView.swift" >/tmp/66tasklight-edge-toggle-compact-catcher.txt; then
  cat /tmp/66tasklight-edge-toggle-compact-catcher.txt
  fail "compact SwiftUI click catchers must not steal drag from the panel"
fi

if rg -n "EdgeRailClickCatcher|requestEdgeRestoreFromRail" "$rail_view" >/tmp/66tasklight-edge-toggle-rail-catcher.txt; then
  cat /tmp/66tasklight-edge-toggle-rail-catcher.txt
  fail "edge rail SwiftUI click catchers must not steal drag from the panel"
fi

rg -q "edgeCollapseRequestID" "$view_model" \
  || fail "view model collapse request command channel is missing"

rg -q "edgeRestoreRequestID" "$view_model" \
  || fail "view model restore request command channel is missing"

rg -q "statusOrbClickCatcher.collapse" "$controller" \
  || fail "panel controller does not observe status orb collapse requests"

rg -q "edgeRailClickCatcher.restore" "$controller" \
  || fail "panel controller does not observe edge rail restore requests"

rg -q "forceRestoreFromEdgePanel" "$controller" \
  || fail "force restore path for edge panel is missing"

rg -q "storedCompactFrame\\.recoveredFromEdgeRail" "$controller" \
  || fail "stored edge-rail frame recovery guard is missing"

rg -q "storedCompactFrame\\.ignoredInvalid" "$controller" \
  || fail "invalid stored compact frame diagnostic is missing"

rg -q "edgeTransitionLockedUntil" "$controller" \
  || fail "edge transition repeat-click lock is missing"

rg -q "restore_bypassed_transition_lock" "$controller" \
  || fail "edge restore should bypass the short transition lock"

rg -q "ignoredAlreadyRestored" "$controller" \
  || fail "already-restored edge click guard is missing"

rg -q "runEdgeToggleSelfTest" "$controller" \
  || fail "edge toggle runtime self-test entrypoint is missing"

rg -q -- "--tasklight-edge-self-test" "$APP_DIR/TaskLightAppDelegate.swift" "$ROOT_DIR/script/build_and_run.sh" \
  || fail "edge toggle runtime self-test launch argument is missing"

rg -q "smoke_luckycat_edge_toggle_runtime" "$ROOT_DIR/script/check_all.sh" \
  || fail "edge toggle runtime self-test is not included in check_all"

rg -q "case edgeRail" "$APP_DIR/TaskLightRootView.swift" \
  || fail "dedicated edge rail display mode is missing"

if rg -n "if viewModel\\.edgeCollapsed" "$APP_DIR/TaskLightRootView.swift" >/tmp/66tasklight-edge-toggle-root-switch.txt; then
  cat /tmp/66tasklight-edge-toggle-root-switch.txt
  fail "compact root should not swap its content based on edgeCollapsed"
fi

rg -q "private var edgePanel: TaskLightPanel" "$controller" \
  || fail "dedicated edge rail panel is missing"

rg -q "createPanel\\(displayMode: \\.edgeRail\\)" "$controller" \
  || fail "edge rail panel creation path is missing"

rg -q "showPanel\\.warmedEdgePanel" "$controller" \
  || fail "edge rail panel should be warmed at startup for first-click speed"

if rg -n "\\.nonactivatingPanel" "$controller" >/tmp/66tasklight-edge-toggle-nonactivating.txt; then
  cat /tmp/66tasklight-edge-toggle-nonactivating.txt
  fail "edge rail should use a regular clickable floating panel"
fi

rg -q "panel\\.roundedHitTestRadius = 0" "$controller" \
  || fail "edge rail panel should not crop its hit target by rounded corners"

rg -q "edgePanel\\.alphaValue = 1" "$controller" \
  || fail "edge rail panel should be explicitly visible on switch"

if rg -n "\\.shadow\\(" "$rail_view" >/tmp/66tasklight-edge-toggle-rail-shadow.txt; then
  cat /tmp/66tasklight-edge-toggle-rail-shadow.txt
  fail "edge rail should not draw rectangular outer shadow"
fi

rg -q "\\.clipShape" "$rail_view" \
  || fail "edge rail should clip its material to the rounded capsule"

rg -q "compactPanel\\.alphaValue = 1" "$controller" \
  || fail "compact panel should be explicitly visible on restore"

rg -q "taskLightEdgeTransitionDuration: TimeInterval = 0\\.10" "$controller" \
  || fail "edge transition budget should stay sub-200ms"

echo "direct_view_writes=0"
echo "legacy_edge_toggle_layers=0"
echo "invisible_interaction_panel=absent"
echo "global_mouse_monitors=absent"
echo "unbounded_mouse_polling=absent"
echo "mouse_up_toggle=absent"
echo "central_compact_click_handler=present"
echo "central_edge_click_handler=present"
echo "click_drag_split=present"
echo "press_duration_gate=present"
echo "drag_event_tracking=present"
echo "long_press_toggle=absent"
echo "edge_free_drag=present"
echo "status_orb_hit_test=present"
echo "compact_body_click_toggle=absent"
echo "delayed_single_click_scheduler=absent"
echo "activation_click_fallback=diagnostic_only"
echo "mouse_event_tap_fallback=present"
echo "controlled_mouse_polling=present"
echo "coordinate_normalization=present"
echo "edge_rectangular_shadow=absent"
echo "click_diagnostics=present"
echo "edge_runtime_click_path_self_test=present"
echo "swiftui_click_catchers=absent"
echo "edge_collapse_panel_channel=present"
echo "edge_restore_panel_channel=present"
echo "dedicated_edge_panel=present"
echo "edge_panel_warmed=present"
echo "edge_panel_nonactivating=absent"
echo "edge_frame_transitions=0.10s"
echo "STATUS=ok"
