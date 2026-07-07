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
chrome_view="$APP_DIR/Screens/EdgeRailGlassChrome.swift"
chrome_background="$APP_DIR/Screens/EdgeRailGlassBackgroundOptics.swift"
chrome_shell="$APP_DIR/Screens/EdgeRailGlassShellLayers.swift"
chrome_primitives="$APP_DIR/Screens/EdgeRailGlassChromePrimitives.swift"
orb_view="$APP_DIR/Screens/EdgeRailGlassStatusOrb.swift"
compact_shell="$APP_DIR/Components/LuckyCatCompactShell.swift"
view_model="$APP_DIR/TaskLightViewModel.swift"
rail_glass_sources=("$rail_view" "$chrome_view" "$chrome_background" "$chrome_shell" "$chrome_primitives")

for source in "${rail_glass_sources[@]}"; do
  [ -f "$source" ] || fail "edge rail glass source is missing: $source"
done

chrome_line_count="$(wc -l <"$chrome_view" | tr -d ' ')"
if [ "$chrome_line_count" -gt 120 ]; then
  fail "edge rail chrome entry should stay lightweight after glass layer extraction"
fi

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

rg -q "collapsed_anchored_from_compact_pass" "$controller" "$ROOT_DIR/script/build_and_run.sh" "$ROOT_DIR/script/smoke_luckycat_edge_toggle_runtime.sh" \
  || fail "runtime self-test should prove collapse anchors from the current compact frame"

rg -q "staleStoredEdgeFrame" "$controller" \
  || fail "runtime self-test should seed a stale stored edge frame before collapse"

rg -Fq "expectedCollapsedEdgeFrame = edgeRailFrame(from: compactDragEndFrame)" "$controller" \
  || fail "runtime self-test should compare collapse target against the current compact frame"

if rg -Fq "storedEdgeRailFrame() ?? edgeRailFrame(from: compactFrame)" "$controller"; then
  fail "collapse from compact must not prefer a stale stored edge-rail frame"
fi

rg -q "edgeRailFramePersistWorkItem" "$controller" \
  || fail "edge rail movement should debounce persisted frame writes"

rg -q "persistImmediately: false" "$controller" \
  || fail "edge rail window move should not synchronously persist every frame"

rg -q "shouldRasterize = true" "$controller" \
  || fail "edge rail hosting layer should be rasterized for smoother dragging"

rg -q "hosting\\.view\\.layer\\?\\.backgroundColor = NSColor\\.clear\\.cgColor" "$controller" \
  || fail "hosting view background must be clear to avoid rectangular backing"

rg -q "panel\\.contentView\\?\\.layer\\?\\.backgroundColor = NSColor\\.clear\\.cgColor" "$controller" \
  || fail "panel content view background must be clear to avoid rectangular backing"

rg -q "transaction.animation = nil" "${rail_glass_sources[@]}" \
  || fail "edge rail should disable implicit SwiftUI animations"

rg -q "edgeRailPanelWidth" "$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/Theme/LuckyCatLayout.swift" "$controller" "${rail_glass_sources[@]}" \
  || fail "edge rail should use a larger transparent panel canvas so 3D glass is not clipped"

rg -q "edgeRailPanelHeight" "$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/Theme/LuckyCatLayout.swift" "$controller" "${rail_glass_sources[@]}" \
  || fail "edge rail should use a taller transparent panel canvas so top/bottom glass is not clipped"

rg -q "NSSize\\(width: LuckyCatLayout\\.edgeRailPanelWidth, height: LuckyCatLayout\\.edgeRailPanelHeight\\)" "$controller" \
  || fail "edge rail panel size must be decoupled from the visible glass card size"

rg -q "edgeRailCornerRadius: CGFloat = 32" "$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/Theme/LuckyCatLayout.swift" \
  || fail "edge rail visible card should use a true capsule radius for clean top and bottom arcs"

rg -q "\\.padding\\(\\.vertical, LuckyCatLayout\\.edgeRailCornerRadius \\+ 9\\)" "${rail_glass_sources[@]}" \
  || fail "left cut highlight must stay well out of the top and bottom arc zones"

rg -q "center: \\.top" "${rail_glass_sources[@]}" \
  || fail "top rail glow should use a curved cap highlight, not a flat strip"

rg -q "center: \\.bottom" "${rail_glass_sources[@]}" \
  || fail "bottom rail glow should use a curved cap highlight, not a flat strip"

rg -q "static let orbSize: CGFloat = 45" "${rail_glass_sources[@]}" \
  || fail "edge rail status orb should keep the larger glass-ball size"

rg -q "fullBodyRefractionVeil" "${rail_glass_sources[@]}" \
  || fail "edge rail V0.20 should carry the bottom glass refraction language through the full capsule body"

rg -q "topArcRim" "${rail_glass_sources[@]}" \
  || fail "edge rail V0.20 should explicitly draw the top capsule arc rim"

rg -q "bottomArcRim" "${rail_glass_sources[@]}" \
  || fail "edge rail V0.20 should explicitly draw the bottom capsule arc rim"

rg -q "capContourRim" "${rail_glass_sources[@]}" \
  || fail "edge rail V0.21 should include explicit top and bottom cap contour rims"

rg -q "EdgeRailCapArc" "${rail_glass_sources[@]}" \
  || fail "edge rail V0.22 should use explicit vector cap arcs for cleaner top and bottom curvature"

rg -q "semanticAccent" "$orb_view" \
  || fail "edge rail status orb should use semantic accent as rim/glow, not recolor the whole glass ball"

rg -q "semanticWashOpacity" "$orb_view" \
  || fail "edge rail V0.22 should make non-running status colors visible through an inner glass refraction wash"

rg -q "#B87916" "${rail_glass_sources[@]}" \
  || fail "edge rail pending title should use a readable deep glass amber, not a pale yellow"

rg -q "orbBodyColors" "$orb_view" \
  || fail "edge rail V0.24 should keep semantic glass body palettes for every status"

rg -q "#44C779" "$orb_view" \
  || fail "edge rail V0.24 should keep Done as a green glass orb, not gray idle"

rg -q "#F05B6C" "$orb_view" \
  || fail "edge rail V0.24 should keep Blocked as a red glass orb"

rg -q "#35C5DD" "$orb_view" \
  || fail "edge rail V0.24 should keep Observed as a cyan glass orb"

rg -q "TaskLightStatus\\.done_verified\\.rawValue" "$view_model" \
  || fail "edge rail V0.24 Done fixture must use the real done_verified status protocol"

if rg -q "status\\.tint\\.opacity\\(0\\.86\\)" "${rail_glass_sources[@]}"; then
  fail "edge rail pending orb must not tint the whole glass ball yellow"
fi

rg -q "LuckyCatEdgeRail3DChrome" "${rail_glass_sources[@]}" \
  || fail "edge rail 2.5D chrome wrapper is missing"

rg -q "rotation3DEffect" "${rail_glass_sources[@]}" \
  || fail "edge rail 2.5D chrome should use native SwiftUI perspective"

rg -q "perspective: EdgeRail3D\\.perspective" "${rail_glass_sources[@]}" \
  || fail "edge rail 2.5D chrome should keep a fixed perspective constant"

rg -q "sideThickness" "${rail_glass_sources[@]}" \
  || fail "edge rail 2.5D chrome should include a side thickness layer"

rg -q "contentReadabilityPlate" "${rail_glass_sources[@]}" \
  || fail "edge rail 2.5D chrome should keep readable front content"

rg -q "glassEffect" "${rail_glass_sources[@]}" \
  || fail "edge rail should prefer native Liquid Glass when available"

rg -Fq "#available(macOS 26.0" "${rail_glass_sources[@]}" \
  || fail "edge rail native glass path must be availability-gated"

rg -q "EdgeRailSystemGlass" "${rail_glass_sources[@]}" \
  || fail "edge rail should isolate system glass and fallback behavior"

if rg -q "ultraThinMaterial" "${rail_glass_sources[@]}"; then
  fail "edge rail fallback should not use heavy material that turns the glass into a white plastic capsule"
fi

rg -q "Color\\.white\\.opacity\\(0\\.020\\)" "${rail_glass_sources[@]}" \
  || fail "edge rail fallback should keep a very light transparent base"

rg -q "subsurfaceDiffusionLayer" "${rail_glass_sources[@]}" \
  || fail "edge rail V0.11 should include a controlled internal diffusion layer"

if rg -q "NSVisualEffectView" "${rail_glass_sources[@]}"; then
  fail "edge rail V0.11 should not keep the ineffective AppKit backdrop experiment"
fi

rg -q "contentPerspectiveLayer" "${rail_glass_sources[@]}" \
  || fail "edge rail content should follow the capsule perspective"

rg -q "contentPitch" "${rail_glass_sources[@]}" \
  || fail "edge rail content perspective should use a fixed mild angle"

rg -q "quotaGlassGroove" "${rail_glass_sources[@]}" \
  || fail "edge rail quota should render as a glass groove"

rg -q "backgroundLiftPlate" "${rail_glass_sources[@]}" \
  || fail "edge rail should include a lifted clean glass background layer"

rg -q "environmentBackgroundLayer" "${rail_glass_sources[@]}" \
  || fail "edge rail should include a weak environment layer for refraction"

rg -q "blurredBackgroundTexture" "${rail_glass_sources[@]}" \
  || fail "edge rail should include a blurred background texture layer"

rg -q "EdgeRailEnvironmentGrid" "${rail_glass_sources[@]}" \
  || fail "edge rail should include a subtle environment grid texture"

rg -q "glassCardBase" "${rail_glass_sources[@]}" \
  || fail "edge rail should include a translucent glass card base"

rg -q "centerLuminosityField" "${rail_glass_sources[@]}" \
  || fail "edge rail should keep the card center bright and transparent, not uniformly gray"

rg -q "edgeThicknessBand" "${rail_glass_sources[@]}" \
  || fail "edge rail should include an inner thickness band, not only a hairline"

rg -q "normalRefractionLayer" "${rail_glass_sources[@]}" \
  || fail "edge rail should include a normal-based refraction approximation"

rg -q "sdfEdgeCutHighlight" "${rail_glass_sources[@]}" \
  || fail "edge rail should include a directionally lit SDF-style cut edge"

rg -q "fresnelRimLight" "${rail_glass_sources[@]}" \
  || fail "edge rail should include a Fresnel rim light layer"

rg -q "bottomRefractionEdge" "${rail_glass_sources[@]}" \
  || fail "edge rail should include a bottom refraction edge"

rg -q "diagonalLightBand" "${rail_glass_sources[@]}" \
  || fail "edge rail should include a directional light band"

if rg -n "cornerSweepHighlight|rearShade" "${rail_glass_sources[@]}" "$orb_view" >/tmp/66tasklight-edge-toggle-dead-glass-layers.txt; then
  cat /tmp/66tasklight-edge-toggle-dead-glass-layers.txt
  fail "edge rail should not keep unused legacy glass experiment layers"
fi

rg -q "floatingShadowLayer" "${rail_glass_sources[@]}" \
  || fail "edge rail should include a floating shadow layer"

rg -q "contactShadowLayer" "${rail_glass_sources[@]}" \
  || fail "edge rail should include a contact shadow layer"

rg -q "Ellipse()" "${rail_glass_sources[@]}" \
  || fail "edge rail shadows should be bottom ellipse layers, not whole-card shadows"

rg -q "straightEdgeMask" "${rail_glass_sources[@]}" \
  || fail "edge rail bevel/rim should use straight-edge masking to keep corners clean"

rg -q "straightEdgeHighlightLayer" "${rail_glass_sources[@]}" \
  || fail "edge rail should split straight-edge highlights from corner bevel"

rg -q "straightEdgeDimLayer" "${rail_glass_sources[@]}" \
  || fail "edge rail should keep bottom/right dimming on straight edges only"

rg -q "silhouetteOutline" "${rail_glass_sources[@]}" \
  || fail "edge rail should keep a light blue-white fallback outline on white backgrounds"

rg -q "glassAlpha: Double = 0\\.10" "${rail_glass_sources[@]}" \
  || fail "edge rail V0.23 should make the center genuinely transparent instead of white plastic"

rg -q "infoPanelAlpha: Double = 0\\.22" "${rail_glass_sources[@]}" \
  || fail "edge rail V0.12 should keep the info panel readable while still glassy"

rg -q "quotaNumber = .*opacity\\(0\\.74\\)" "${rail_glass_sources[@]}" \
  || fail "edge rail V0.22 should keep quota text readable on transparent glass"

rg -q "statusTextColor\\.opacity\\(0\\.095\\)" "${rail_glass_sources[@]}" \
  || fail "edge rail V0.22 should tint the status title glass with a readable semantic status color"

rg -q "statusTextColor\\.opacity\\(0\\.22\\)" "${rail_glass_sources[@]}" \
  || fail "edge rail V0.22 should tint the status title rim with a readable semantic status color"

if rg -q "glassPrismRose\\.opacity\\(0\\.(0[2-9][0-9]|[1-9][0-9][0-9])\\)" "${rail_glass_sources[@]}"; then
  fail "edge rail V0.10 should not reintroduce visible pink/purple glass contamination"
fi

rg -q "centerAlpha: Double = 0\\.45" "${rail_glass_sources[@]}" \
  || fail "edge rail V0.6 should expose the lowered center alpha parameter"

rg -q "edgeAlpha: Double = 0\\.94" "${rail_glass_sources[@]}" \
  || fail "edge rail V0.5 should keep a stronger edge glass shell"

rg -q "rimIntensity: Double = 0\\.96" "${rail_glass_sources[@]}" \
  || fail "edge rail V0.5 should restore cut-edge highlight intensity"

rg -q "saturate: Double = 1\\.12" "${rail_glass_sources[@]}" \
  || fail "edge rail V0.5 should reduce saturation to avoid color pollution"

rg -q "#72DB93" "${rail_glass_sources[@]}" \
  || fail "edge rail done status title should use the readable liquid-glass green"

if rg -n "bottomDepthShade" "${rail_glass_sources[@]}" >/tmp/66tasklight-edge-toggle-bottom-depth-shade.txt; then
  cat /tmp/66tasklight-edge-toggle-bottom-depth-shade.txt
  fail "edge rail should not use a full-width bottom depth shade that dirties corners"
fi

rg -q "microNoiseLayer" "${rail_glass_sources[@]}" \
  || fail "edge rail should include a subtle micro-noise layer"

rg -q "EdgeRailGlassStatusOrb" "${rail_glass_sources[@]}" \
  || fail "edge rail should use a dedicated glass status orb"

rg -q "countGlassAirLayer" "${rail_glass_sources[@]}" \
  || fail "edge rail info panel should be a light glass label, not a heavy gray insert"

rg -q "EdgeRailLiquidGlassV04" "${rail_glass_sources[@]}" \
  || fail "edge rail should expose the V0.4 Liquid Glass parameter model"

for param in glassAlpha blur saturate brightness edgeThickness rimIntensity refractionStrength bottomShadow floatShadow contactShadow orbSize orbRimOpacity infoPanelAlpha; do
  rg -q "$param" "${rail_glass_sources[@]}" \
    || fail "edge rail Liquid Glass parameter is missing: $param"
done

for v04_param in centerAlpha edgeAlpha centerStrength edgeStrength cornerStrength outerHighlight innerHighlight rightShadow sweepOpacity; do
  rg -q "$v04_param" "${rail_glass_sources[@]}" \
    || fail "edge rail V0.4 parameter is missing: $v04_param"
done

if rg -n "Image\\(|NSImage|resizable\\(" "${rail_glass_sources[@]}" >/tmp/66tasklight-edge-toggle-rail-static-art.txt; then
  cat /tmp/66tasklight-edge-toggle-rail-static-art.txt
  fail "edge rail should not fake the glass card with static art"
fi

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

if rg -n "entranceVisible|withAnimation|scaleEffect" "${rail_glass_sources[@]}" >/tmp/66tasklight-edge-toggle-rail-animation.txt; then
  cat /tmp/66tasklight-edge-toggle-rail-animation.txt
  fail "edge rail should not run entrance scale animations that can stutter dragging"
fi

if rg -n "pulsing: status == \\.running|pulsing: true" "${rail_glass_sources[@]}" >/tmp/66tasklight-edge-toggle-rail-pulse.txt; then
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

if rg -n "EdgeRailClickCatcher|requestEdgeRestoreFromRail" "${rail_glass_sources[@]}" >/tmp/66tasklight-edge-toggle-rail-catcher.txt; then
  cat /tmp/66tasklight-edge-toggle-rail-catcher.txt
  fail "edge rail SwiftUI click catchers must not steal drag from the panel"
fi

rg -q "edgeCollapseRequestID" "$view_model" \
  || fail "view model collapse request command channel is missing"

rg -q "edgeRestoreRequestID" "$view_model" \
  || fail "view model restore request command channel is missing"

rg -q "self\\.edgeCollapsed = false" "$view_model" \
  || fail "app launch should default to the full compact cat instead of restoring the edge rail"

rg -q "defaults\\.set\\(false, forKey: TaskLightLedgerKeys\\.edgeCollapsed\\)" "$view_model" \
  || fail "app launch should clear stale edge rail persistence before showing the compact cat"

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

rg -q "startupTopRightCompactFrame" "$controller" \
  || fail "compact startup placement should use an explicit top-right frame helper"

rg -q "preferredStartupCompactFrame\\.topRightLaunch" "$controller" \
  || fail "compact startup placement should trace the top-right launch policy"

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

if rg -n "\\.shadow\\(" "${rail_glass_sources[@]}" >/tmp/66tasklight-edge-toggle-rail-shadow.txt; then
  cat /tmp/66tasklight-edge-toggle-rail-shadow.txt
  fail "edge rail should not draw rectangular outer shadow"
fi

rg -q "\\.clipShape" "${rail_glass_sources[@]}" \
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
echo "edge_3d_chrome=present"
echo "edge_liquid_glass_path=present"
echo "edge_content_perspective=present"
echo "edge_static_art=absent"
echo "edge_five_layer_glass=present"
echo "edge_liquid_glass_v2=present"
echo "edge_liquid_glass_v04_chain=present"
echo "edge_corner_shadow_split=present"
echo "edge_liquid_glass_v05_solidity=present"
echo "edge_liquid_glass_v06_corner_attenuation=present"
echo "edge_liquid_glass_v10_transparent_body=present"
echo "edge_liquid_glass_v11_internal_diffusion=present"
echo "edge_liquid_glass_v12_content_clarity=present"
echo "edge_liquid_glass_v13_status_semantic_glass=present"
echo "edge_liquid_glass_v14_panel_safe_canvas=present"
echo "edge_liquid_glass_v15_capsule_arc_clean=present"
echo "edge_liquid_glass_v19_curved_cap_glow=present"
echo "edge_liquid_glass_v20_full_body_refraction=present"
echo "edge_liquid_glass_v20_semantic_orb_accent=present"
echo "edge_liquid_glass_v21_cap_contour_rim=present"
echo "edge_liquid_glass_v21_left_feather_suppressed=present"
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
