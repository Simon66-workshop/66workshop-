#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TYPES="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift"
STORE="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightStore.swift"
VM="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift"
RADAR="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/Screens/TaskRadarPopoverView.swift"
MENU="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/TaskLightMenuBarController.swift"

fail() {
  echo "STATUS=fail"
  echo "reason=$1"
  exit 1
}

rg -q "struct WorkspaceDoctorRow" "$TYPES" || fail "WorkspaceDoctorRow type is missing"
rg -q "loadWorkspaceDoctorRows" "$STORE" "$VM" || fail "workspace doctor rows are not loaded from coverage report"
rg -q "workspaceCoverageLatestJSONURL" "$STORE" || fail "doctor must reuse workspace coverage latest.json"
for status in invalid_hooks missing_hooks installed_needs_trust not_loaded diagnostic_only trusted; do
  rg -q "$status" "$STORE" || fail "doctor classification missing: $status"
done
rg -q "Hooks Doctor" "$RADAR" || fail "task radar must render Hooks Doctor"
rg -q "打开 Hooks Doctor" "$MENU" || fail "menu bar must expose Hooks Doctor"
rg -q "手动 Trust" "$RADAR" || fail "doctor must tell user trust is manual"
rg -q "安装说明" "$RADAR" || fail "doctor must expose an install guide entry"
rg -q "openWorkspaceHooksGuide" "$VM" "$RADAR" || fail "doctor install guide action is missing"
rg -q "CODEX_WORKSPACE_ONBOARDING.md" "$VM" || fail "doctor guide must point to workspace onboarding docs"
rg -q "不会自动修改任务状态" "$RADAR" || fail "doctor must state it will not mutate task status"

if rg -n "auto.*trust|trust.*auto|requestTrust|approveHooks|trustHooks|--trust" "$STORE" "$VM" "$RADAR" "$MENU" >/tmp/66tasklight-doctor-auto-trust.txt; then
  cat /tmp/66tasklight-doctor-auto-trust.txt
  fail "workspace doctor must not auto trust hooks"
fi

echo "smoke_workspace_hooks_doctor=ok"
echo "STATUS=ok"
