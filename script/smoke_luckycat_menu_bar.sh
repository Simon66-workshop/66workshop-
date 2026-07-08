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

rg -q "onOpenVisualMatrix" "$controller" "$radar" \
  || fail "task radar popover should expose a direct visual matrix action"

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

rg -q "toggleExpandedFromMenuBar" "$panel" "$controller" \
  || fail "menu bar expanded panel should be a toggle action"

rg -q "closeExpandedFromMenuBar" "$panel" \
  || fail "menu bar expanded panel close action is missing"

rg -q "viewModel\\.expanded \\? \"关闭完整面板\" : \"打开完整面板\"" "$controller" \
  || fail "expanded panel menu title should switch between open and close"

rg -q "#selector\\(toggleExpandedPanel\\)" "$controller" \
  || fail "expanded panel menu item should call the toggle selector"

if rg -n "NSMenuItem\\(title: \"打开完整面板\", action:" "$controller" >/tmp/66tasklight-expanded-static-title.txt; then
  cat /tmp/66tasklight-expanded-static-title.txt
  fail "expanded panel menu item title must not be static"
fi

rg -q "statusItem\\.menu = statusMenu" "$controller" \
  || fail "menu bar should use native statusItem.menu for reliable menu display"

rg -q "func menuWillOpen" "$controller" \
  || fail "native status menu should refresh before opening"

rg -q "func menuNeedsUpdate" "$controller" \
  || fail "native status menu should rebuild dynamic titles before opening"

rg -q "guard !isStatusMenuOpen else" "$controller" \
  || fail "status item updates must be deferred while the native menu is tracking"

rg -q "statusNeedsRefreshAfterMenuClose = true" "$controller" \
  || fail "menu bar should remember deferred status refreshes while menu is open"

sed -n '/func menuDidClose/,/^    private func togglePopover/p' "$controller" > /tmp/66tasklight-menu-close-section.txt
if rg -n "rebuildStatusMenu\\(" /tmp/66tasklight-menu-close-section.txt >/tmp/66tasklight-menu-close-rebuild.txt; then
  cat /tmp/66tasklight-menu-close-rebuild.txt
  fail "menuDidClose must not synchronously rebuild the menu after every menu tracking session"
fi

sed -n '/private func togglePopover/,/^    private func rebuildStatusMenu/p' "$controller" > /tmp/66tasklight-menu-popover-section.txt
if rg -n "NSApp\\.activate" /tmp/66tasklight-menu-popover-section.txt >/tmp/66tasklight-menu-popover-activate.txt; then
  cat /tmp/66tasklight-menu-popover-activate.txt
  fail "task radar popover should not activate the app during menu tracking"
fi

sed -n '/private func appendMenuTrace/,/^}/p' "$controller" > /tmp/66tasklight-menu-trace-section.txt
rg -q "taskLightTraceWriteQueue\\.async" /tmp/66tasklight-menu-trace-section.txt \
  || fail "menu trace writes must be asynchronous and serialized so menu hover and actions stay responsive"

if rg -n "performClick\\(nil\\)|statusItem\\.menu = nil|popUpMenu|menu\\.popUp\\(" "$controller" >/tmp/66tasklight-menu-sticky-popup.txt; then
  cat /tmp/66tasklight-menu-sticky-popup.txt
  fail "menu bar must not use synthetic menu clicks or manual popup positioning"
fi

rg -q "打开视觉矩阵" "$controller" \
  || fail "menu bar context menu should expose the visual matrix"

rg -q "isVisualMatrixVisible \\? \"关闭视觉矩阵\" : \"打开视觉矩阵\"" "$controller" \
  || fail "visual matrix menu title should switch between open and close"

rg -q "#selector\\(toggleVisualMatrix\\)" "$controller" \
  || fail "visual matrix menu item should call the toggle selector"

rg -q "closeVisualMatrixWindow" "$controller" \
  || fail "visual matrix close action is missing"

if rg -n "NSMenuItem\\(title: \"打开视觉矩阵\", action:" "$controller" >/tmp/66tasklight-matrix-static-title.txt; then
  cat /tmp/66tasklight-matrix-static-title.txt
  fail "visual matrix menu item title must not be static"
fi

rg -q "makeVisualMatrixWindowController" "$controller" \
  || fail "visual matrix should open in a dedicated window"

rg -q "orderFrontRegardless\\(\\)" "$controller" \
  || fail "visual matrix window should be forced to the front when opened"

rg -q "runVisualMatrixSelfTest" "$controller" \
  || fail "visual matrix should have a real runtime self-test hook"

rg -q "runMenuBarSelfTest" "$controller" \
  || fail "menu bar popover should have a real runtime self-test hook"

if rg -n "prewarmVisualMatrixWindow|warmVisualMatrixWindow|alphaValue = 0" "$controller" >/tmp/66tasklight-menu-prewarm-window.txt; then
  cat /tmp/66tasklight-menu-prewarm-window.txt
  fail "visual matrix must not use invisible prewarm windows that can steal focus or clicks"
fi

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
