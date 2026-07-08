#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TYPES="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift"
STORE="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightStore.swift"
VM="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift"
RADAR="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/Screens/TaskRadarPopoverView.swift"

fail() {
  echo "smoke_workspace_hooks_install_confirm: $*" >&2
  exit 1
}

rg -q "struct WorkspaceHookInstallRequest" "$TYPES" || fail "install request type is missing"
rg -q "requires_user_confirmation" "$TYPES" "$STORE" || fail "install request must require confirmation"
rg -q "confirmationDialog" "$RADAR" || fail "UI confirmation dialog is missing"
rg -q "install_hooks_for_workspaces\\.sh" "$STORE" || fail "installer script is not wired"
rg -q "manual Trust|手动 Trust" "$STORE" "$RADAR" || fail "manual Trust reminder is missing"

if rg -n "requestTrust|approveHooks|trustHooks|--trust" "$STORE" "$VM" "$RADAR" >/tmp/66tasklight-install-trust-risk.txt; then
  cat /tmp/66tasklight-install-trust-risk.txt
  fail "installer must not include trust automation"
fi

echo "smoke_workspace_hooks_install_confirm=ok"
echo "STATUS=ok"

