#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TYPES="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift"
STORE="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightStore.swift"
VM="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift"
RADAR="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/Screens/TaskRadarPopoverView.swift"

fail() {
  echo "smoke_quota_burn_rate_maturity: $*" >&2
  exit 1
}

rg -q "enum QuotaBurnRateConfidence" "$TYPES" || fail "quota confidence enum is missing"
for status in insufficient warming stable stale; do
  rg -q "case $status" "$TYPES" || fail "quota confidence $status is missing"
done
rg -q "burnRateSegmentAfterLatestReset" "$VM" || fail "quota reset/recovery baseline logic is missing"
rg -q "pruneQuotaHistoryIfNeeded" "$STORE" || fail "quota history retention is missing"
rg -q "confidence" "$RADAR" "$VM" || fail "quota confidence is not surfaced"

if rg -n "global_status.*quota|lamp_status.*quota|quota.*global_status|quota.*lamp_status" "$VM" "$STORE" "$TYPES" >/tmp/66tasklight-quota-main-lamp-risk.txt; then
  cat /tmp/66tasklight-quota-main-lamp-risk.txt
  fail "quota maturity must not affect main lamp"
fi

echo "smoke_quota_burn_rate_maturity=ok"
echo "STATUS=ok"

