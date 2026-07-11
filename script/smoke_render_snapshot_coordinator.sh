#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COORDINATOR="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightRenderSnapshotCoordinator.swift"
VM="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift"
BUDGET="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightUIPerformanceBudget.swift"

fail() {
  echo "smoke_render_snapshot_coordinator: $*" >&2
  exit 1
}

rg -q "struct TaskLightRenderSnapshot" "$COORDINATOR" || fail "shared render snapshot is missing"
rg -q "pendingCompletions" "$COORDINATOR" || fail "snapshot refreshes are not coalesced"
rg -q -F 'DispatchQueue(label: "com.66tasklight.render-snapshot"' "$COORDINATOR" || fail "snapshot reads are not serialized off the main surface"
rg -q "renderSnapshotCoordinator.refresh" "$VM" || fail "view model does not use the snapshot coordinator"
rg -q "workspaceDoctorSnapshot" "$VM" || fail "workspace doctor must render from the shared snapshot"
rg -q "statusReplaySnapshot" "$VM" || fail "status replay must render from the shared snapshot"
rg -q "quotaHistorySnapshot" "$VM" || fail "quota pace must render from the shared snapshot"
rg -q "renderSnapshotLoadMaxMilliseconds" "$BUDGET" || fail "snapshot performance budget is missing"

if rg -n "loadWorkspaceDoctorRows\(|loadStatusReplayRecords\(|loadQuotaHistory\(|loadExternalUsageProviderSnapshots\(" "$VM" >/tmp/66tasklight-main-thread-read-risk.txt; then
  cat /tmp/66tasklight-main-thread-read-risk.txt
  fail "view model must not synchronously load auxiliary files on the UI path"
fi

echo "smoke_render_snapshot_coordinator=ok"
echo "STATUS=ok"
