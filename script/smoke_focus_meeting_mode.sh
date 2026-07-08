#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TYPES="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift"
VM="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift"
MENU="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/TaskLightMenuBarController.swift"
PANEL="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/TaskLightPanelController.swift"

fail() {
  echo "STATUS=fail"
  echo "reason=$1"
  exit 1
}

rg -q "enum TaskLightPresenceMode" "$TYPES" || fail "TaskLightPresenceMode is missing"
for mode in normal focusCapsule menuBarOnly; do
  rg -q "case $mode" "$TYPES" || fail "presence mode missing: $mode"
done
rg -q "TaskLightPresenceMode" "$VM" "$MENU" "$PANEL" || fail "presence mode is not wired through VM/menu/panel"
rg -q "setPresenceMode" "$VM" "$MENU" "$PANEL" || fail "presence mode setter is missing"
rg -q "applyPresenceModeFromMenuBar" "$PANEL" "$MENU" || fail "panel presence-mode bridge is missing"
rg -q "Focus 模式" "$MENU" || fail "menu bar must expose Focus mode"
rg -q "只留菜单栏" "$MENU" || fail "menu bar must expose menu-bar-only mode"
rg -q "autoMeetingMode" "$TYPES" || fail "auto meeting preference key should exist and stay opt-in"
rg -q "autoMeetingModeEnabled" "$VM" "$MENU" || fail "auto meeting mode switch should be visible and persisted"
rg -q "会议自动降存在感" "$MENU" || fail "menu bar must expose auto meeting low-profile switch"

if rg -n "global_status|lamp_status|clearTask|store\\.clear" "$VM" "$MENU" "$PANEL" | rg "Presence|presence|Focus|focus|menuBarOnly" >/tmp/66tasklight-focus-status.txt; then
  cat /tmp/66tasklight-focus-status.txt
  fail "Focus mode must not change main status or clear tasks"
fi

echo "smoke_focus_meeting_mode=ok"
echo "STATUS=ok"
