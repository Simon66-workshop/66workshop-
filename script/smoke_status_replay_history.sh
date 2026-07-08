#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TYPES="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift"
STORE="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightStore.swift"
VM="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift"
RADAR="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/Screens/TaskRadarPopoverView.swift"

fail() {
  echo "STATUS=fail"
  echo "reason=$1"
  exit 1
}

rg -q "struct StatusReplayRecord" "$TYPES" || fail "StatusReplayRecord type is missing"
rg -q "loadStatusReplayRecords" "$STORE" "$VM" || fail "status replay reader is missing"
rg -q "uiEventFlowURL" "$STORE" || fail "status replay must reuse ui_event_flow.jsonl"
rg -q "statusReplayRecords\\(hours: 24" "$RADAR" "$VM" || fail "status replay must default to 24h surface"
rg -q "24h Status Replay" "$RADAR" || fail "task radar must render 24h Status Replay"
for marker in process_only old_writer multiple_projector stale_launch_agent runtime_score_below_threshold fallback_reason; do
  rg -q "$marker" "$STORE" || fail "status replay marker missing: $marker"
done
rg -q "copyStatusReplayEvidence" "$VM" "$RADAR" || fail "status replay evidence copy action is missing"

if rg -n "prompt|auth\\.json|authorization|raw log|raw_log|raw_body|log_body" "$STORE" "$VM" "$RADAR" >/tmp/66tasklight-replay-sensitive.txt; then
  cat /tmp/66tasklight-replay-sensitive.txt
  fail "status replay must stay sanitized and not expose prompt/response/auth/raw body"
fi

echo "smoke_status_replay_history=ok"
echo "STATUS=ok"
