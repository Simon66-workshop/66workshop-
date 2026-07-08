#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp"

fail() {
  echo "STATUS=fail"
  echo "reason=$1"
  exit 1
}

controller="$APP_DIR/TaskLightMenuBarController.swift"
view_model="$APP_DIR/TaskLightViewModel.swift"
app_delegate="$APP_DIR/TaskLightAppDelegate.swift"
radar="$APP_DIR/Screens/TaskRadarPopoverView.swift"
panel="$APP_DIR/TaskLightPanelController.swift"

[ -f "$controller" ] || fail "TaskLightMenuBarController is missing"
[ -f "$radar" ] || fail "TaskRadarPopoverView is missing"

rg -q "NSStatusItem\\.variableLength" "$controller" \
  || fail "menu bar must use a variable length NSStatusItem"

rg -q "TaskRadarPopoverView\\(viewModel: viewModel\\)" "$controller" \
  || fail "menu bar popover must host TaskRadarPopoverView"

rg -q "menuBarStatusTitle\\(\\)" "$view_model" "$controller" \
  || fail "menu bar title helper is missing"

rg -q "menuBarStatusAccessibilityLabel\\(\\)" "$view_model" "$controller" \
  || fail "menu bar accessibility helper is missing"

rg -q "taskRadarActiveTasks\\(\\)" "$view_model" "$radar" \
  || fail "task radar active task helper is missing"

rg -q "taskRadarObservedThreads\\(\\)" "$view_model" "$radar" \
  || fail "task radar observed thread helper is missing"

rg -q "taskRadarDiagnosticRows\\(\\)" "$view_model" "$radar" \
  || fail "task radar diagnostic helper is missing"

rg -q "TaskLightMenuBarController\\(viewModel: viewModel, panelController: controller\\)" "$app_delegate" \
  || fail "app delegate must create menu bar controller with shared view model"

rg -q "togglePanelVisibilityFromMenuBar" "$panel" "$controller" \
  || fail "menu bar visibility action is missing"

rg -q "toggleEdgeRailFromMenuBar" "$panel" "$controller" \
  || fail "menu bar edge rail action is missing"

rg -q "openExpandedFromMenuBar" "$panel" "$controller" \
  || fail "menu bar expanded panel action is missing"

rg -q "popover\\.close\\(\\)" "$controller" \
  || fail "right-click menu should close the task radar popover before opening the context menu"

sed -n '/func toggleEdgeRailFromMenuBar/,/^    func /p' "$panel" > /tmp/66tasklight-menu-edge-toggle-section.txt
if rg -n "showCurrentModeFromMenuBar" /tmp/66tasklight-menu-edge-toggle-section.txt >/tmp/66tasklight-menu-double-transition.txt; then
  cat /tmp/66tasklight-menu-double-transition.txt
  fail "menu bar edge rail toggle should not force a second manual transition"
fi

if rg -n "TaskLightStatus\\.(running|blocked|done_verified|done_unverified)|global_status|lamp_status" "$controller" "$radar" >/tmp/66tasklight-menu-status-algorithm.txt; then
  cat /tmp/66tasklight-menu-status-algorithm.txt
  fail "menu bar and radar views must not reimplement main status semantics"
fi

rg -q "Quota is diagnostic only; main lamp remains ui_state driven" "$radar" \
  || fail "task radar must state quota is diagnostic only"

echo "STATUS=ok"
