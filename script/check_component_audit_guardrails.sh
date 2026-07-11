#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/mac/66TaskLight"
PANEL="$PACKAGE_DIR/Sources/TaskLightApp/TaskLightPanelController.swift"
VIEW_MODEL="$PACKAGE_DIR/Sources/TaskLightApp/TaskLightViewModel.swift"
MACHINE="$PACKAGE_DIR/Sources/TaskLightCore/TaskLightInteractionStateMachine.swift"
PREVIEW="$PACKAGE_DIR/Sources/TaskLightApp/Preview/LuckyCatPreviewData.swift"
TESTS="$PACKAGE_DIR/Tests/TaskLightTestSuite/TaskLightCoreTestSuite.swift"

fail() {
  echo "STATUS=fail"
  echo "reason=$1"
  exit 1
}

if rg -q 'defaults\.set\(false, forKey: TaskLightLedgerKeys\.edgeCollapsed\)' "$VIEW_MODEL"; then
  fail "edge collapsed persistence is reset during startup"
fi

rg -q 'TaskLightInteractionStateMachine' "$PANEL" "$MACHINE" || fail "single interaction state machine is missing"
rg -q 'NSEvent\.mouseEvent' "$PANEL" || fail "AppKit event replay path is missing"
rg -q 'Interaction state machine keeps tap, double tap, drag, and long press distinct' "$TESTS" || fail "interaction reducer regression test is missing"
rg -q '@MainActor' "$PREVIEW" || fail "visual matrix fixture actor isolation is missing"

check_line_budget() {
  local path="$1"
  local limit="$2"
  local lines
  lines="$(wc -l < "$path" | tr -d ' ')"
  [ "$lines" -le "$limit" ] || fail "$(basename "$path") exceeds $limit lines ($lines)"
}

check_line_budget "$PANEL" 2300
check_line_budget "$VIEW_MODEL" 2000

(cd "$PACKAGE_DIR" && swift build) >/dev/null || fail "Swift component audit build failed"
(cd "$PACKAGE_DIR" && swift run TaskLightTestRunner) >/dev/null || fail "Swift component audit tests failed"

echo "component_audit_guardrails=ok"
echo "STATUS=ok"
