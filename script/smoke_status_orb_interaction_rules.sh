#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TYPES="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift"
VM="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift"
PANEL="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/TaskLightPanelController.swift"
BUILD="$ROOT_DIR/script/build_and_run.sh"
RUNTIME="$ROOT_DIR/script/smoke_luckycat_edge_toggle_runtime.sh"

fail() {
  echo "STATUS=fail"
  echo "reason=$1"
  exit 1
}

rg -q "struct InteractionRuleSelfTestResult" "$TYPES" || fail "InteractionRuleSelfTestResult type is missing"
rg -q "interactionRulesSummary" "$VM" || fail "interaction rules presentation helper is missing"
rg -Fq "private let taskLightDragThreshold: CGFloat = 4" "$PANEL" || fail "drag threshold should be standardized at 4pt"
rg -Fq "private let taskLightClickMaxDuration: TimeInterval = 0.45" "$PANEL" || fail "long press threshold should be 450ms"
rg -q "restore_single_click" "$PANEL" || fail "capsule single click should restore full cat"
rg -q "double_click_open_diagnostics" "$PANEL" || fail "compact status orb double click should open diagnostics"
rg -q "press_hold_no_toggle" "$PANEL" || fail "long press no-toggle diagnostic is missing"
rg -q "drag_begin" "$PANEL" || fail "drag begin diagnostic is missing"
rg -q "edge_single_click_restore_pass" "$PANEL" "$BUILD" "$RUNTIME" || fail "runtime self-test must prove capsule single-click restore"
rg -q "drag_threshold_prevents_toggle" "$PANEL" || fail "interaction runtime payload should include drag threshold proof"

if rg -n "instantStatusOrbDown|instant_status_orb_down|compact_status_orb_mouse_down" "$PANEL" >/tmp/66tasklight-status-orb-instant.txt; then
  cat /tmp/66tasklight-status-orb-instant.txt
  fail "status orb must not toggle before drag/long-press intent is known"
fi

echo "smoke_status_orb_interaction_rules=ok"
echo "STATUS=ok"
