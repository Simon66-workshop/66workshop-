#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCREEN_DIR="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/Screens"
MAIN="$SCREEN_DIR/LuckyCatEdgeRailView.swift"

fail() {
  echo "smoke_edge_glass_module_boundaries: $*" >&2
  exit 1
}

for file in \
  EdgeRailGlassChrome.swift \
  EdgeRailGlassChromePrimitives.swift \
  EdgeRailGlassBackgroundOptics.swift \
  EdgeRailGlassShellLayers.swift \
  EdgeRailGlassStatusOrb.swift; do
  [[ -f "$SCREEN_DIR/$file" ]] || fail "$file is missing"
done

main_lines="$(wc -l < "$MAIN" | tr -d ' ')"
[[ "$main_lines" -le 340 ]] || fail "LuckyCatEdgeRailView.swift is too large: $main_lines lines"

rg -q "LuckyCatEdgeRail3DChrome" "$MAIN" "$SCREEN_DIR/EdgeRailGlassChrome.swift" || fail "edge rail chrome wrapper is not used"
rg -q "EdgeRailGlassStatusOrb" "$MAIN" "$SCREEN_DIR/EdgeRailGlassStatusOrb.swift" || fail "status orb component is not isolated"

if rg -n "Image\\(|NSImage|\\.png|\\.jpg|screenshot|overlay image" "$MAIN" "$SCREEN_DIR"/EdgeRailGlass*.swift >/tmp/66tasklight-edge-static-art.txt; then
  cat /tmp/66tasklight-edge-static-art.txt
  fail "edge glass must use native primitives, not static art overlays"
fi

echo "smoke_edge_glass_module_boundaries=ok"
echo "STATUS=ok"

