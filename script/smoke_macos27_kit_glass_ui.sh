#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp"

fail() {
  echo "STATUS=fail"
  echo "reason=$1"
  exit 1
}

glass="$APP_DIR/Components/MacOSKitGlass.swift"
radar="$APP_DIR/Screens/TaskRadarPopoverView.swift"
matrix="$APP_DIR/Preview/LuckyCatVisualStateMatrixView.swift"
menu="$APP_DIR/TaskLightMenuBarController.swift"

[ -f "$glass" ] || fail "macOS kit glass primitive is missing"
[ -f "$radar" ] || fail "task radar view is missing"
[ -f "$matrix" ] || fail "visual matrix view is missing"

rg -q "struct MacOSKitGlassSurface" "$glass" \
  || fail "macOS kit glass surface primitive is missing"
rg -q "MacOSKitGlassBackground" "$glass" \
  || fail "macOS kit glass background primitive is missing"
rg -q "ultraThinMaterial|thinMaterial" "$glass" \
  || fail "macOS kit glass must use native material fallback"
rg -q "largeCardRadius" "$glass" \
  || fail "macOS kit glass should carry large liquid-glass radius token"
rg -q "MacOSKitFloatingShadow" "$glass" \
  || fail "macOS kit glass should split floating shadow from the rounded card body"
rg -q "Ellipse\\(\\)" "$glass" \
  || fail "macOS kit floating shadow should use bottom-centered ellipses"

if rg -n "shape[[:space:][:punct:]]*\\.fill\\(MacOSKitGlass\\.coldShadow|RoundedRectangle\\([^\\n]*\\)[[:space:][:punct:]]*\\.fill\\(MacOSKitGlass\\.coldShadow" "$glass" >/tmp/66tasklight-kit-body-shadow.txt; then
  cat /tmp/66tasklight-kit-body-shadow.txt
  fail "glass card body must not carry rounded-rectangle outer shadows"
fi

rg -q "MacOSKitGlassBackground\\(\\)" "$radar" "$matrix" \
  || fail "radar and matrix should use the shared macOS kit glass background"
rg -q "macOSKitGlassCard" "$radar" "$matrix" \
  || fail "radar and matrix should use shared glass card primitives"
rg -q "macOSKitGlassChip" "$radar" "$matrix" \
  || fail "radar and matrix should use shared glass chip primitives"

rg -q "LazyVStack" "$radar" \
  || fail "task radar diagnostic content should lazy render"
rg -q "taskRadarActiveTasks\\(limit: 6\\)" "$radar" \
  || fail "task radar should request a bounded active task list"
rg -q "taskRadarObservedThreads\\(limit: 4\\)" "$radar" \
  || fail "task radar should request a bounded observed thread list"
rg -q "MacOSKitGlassSurface\\(cornerRadius: cornerRadius, shadow: cornerRadius >= 18\\)" "$radar" \
  || fail "nested radar cards should avoid repeated outer shadows"
rg -q "DispatchQueue\\.main\\.asyncAfter\\(deadline: \\.now\\(\\) \\+ 0\\.05\\)" "$radar" \
  || fail "task radar should use a fast two-phase shell for first paint"
rg -q "LightweightLuckyCatPreview" "$matrix" \
  || fail "visual matrix should use lightweight compact previews"
rg -q "LightweightEdgeRailPreview" "$matrix" \
  || fail "visual matrix should use lightweight edge previews"

if rg -n "TaskLightViewModel\\(|@StateObject|LuckyCatCompactView\\(|LuckyCatEdgeRailView\\(|scaleEffect\\(" "$matrix" >/tmp/66tasklight-kit-heavy-matrix.txt; then
  cat /tmp/66tasklight-kit-heavy-matrix.txt
  fail "visual matrix must not embed heavy runtime components that cause scroll and toggle lag"
fi

if rg -n "asyncAfter\\(deadline: \\.now\\(\\) \\+ 0\\.(1[6-9]|[2-9][0-9])|ProgressView\\(\\).*正在载入" "$matrix" "$radar" >/tmp/66tasklight-kit-delay.txt; then
  cat /tmp/66tasklight-kit-delay.txt
  fail "macOS kit surfaces must not reintroduce visible loading delay"
fi

if rg -n "figma\\.com|screenshot|overlayImage|Image\\(\".*glass|asset.*Liquid Glass|\\.png|\\.jpg" "$glass" "$radar" "$matrix" >/tmp/66tasklight-kit-static-art.txt; then
  cat /tmp/66tasklight-kit-static-art.txt
  fail "macOS kit glass must not be faked with static art or screenshots"
fi

if rg -n "TaskLightStatus\\.(running|blocked|done_verified|done_unverified)|global_status|lamp_status|auth\\.json" "$glass" "$radar" "$matrix" "$menu" >/tmp/66tasklight-kit-status-leak.txt; then
  cat /tmp/66tasklight-kit-status-leak.txt
  fail "glass UI layer must not reimplement status semantics or touch secrets"
fi

echo "smoke_macos27_kit_glass_ui=ok"
echo "STATUS=ok"
