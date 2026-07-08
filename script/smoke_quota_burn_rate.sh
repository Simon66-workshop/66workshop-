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

rg -q "struct QuotaBurnRateSnapshot" "$TYPES" || fail "QuotaBurnRateSnapshot type is missing"
rg -q "struct QuotaBurnRateWindow" "$TYPES" || fail "QuotaBurnRateWindow type is missing"
rg -q "struct QuotaHistorySample" "$TYPES" || fail "QuotaHistorySample type is missing"
rg -q "quotaHistoryURL" "$TYPES" || fail "quota_history path is not configured"
rg -q "quota_history\\.jsonl" "$TYPES" || fail "quota history must use sanitized jsonl"
rg -q "appendQuotaHistorySample" "$STORE" "$VM" || fail "quota history append path is missing"
rg -q "loadQuotaHistory" "$STORE" "$VM" || fail "quota history read path is missing"
rg -q "samples\\.count >= 3" "$VM" || fail "burn-rate must require at least 3 samples"
rg -q "burn_percent_per_hour" "$TYPES" "$VM" "$RADAR" || fail "burn-rate per hour field is missing"
rg -q "estimated_empty_at" "$TYPES" "$VM" || fail "estimated empty time field is missing"
rg -q "low_quota" "$VM" "$RADAR" || fail "low quota warning path is missing"
rg -q "Quota Pace" "$RADAR" || fail "task radar must render Quota Pace"

if rg -n "global_status|lamp_status" "$STORE" "$VM" | rg "quotaBurnRateSnapshot|burnRateWindow|appendQuotaHistorySample|quotaHistory" >/tmp/66tasklight-quota-main-lamp.txt; then
  cat /tmp/66tasklight-quota-main-lamp.txt
  fail "quota burn-rate code must not change main lamp status"
fi

echo "smoke_quota_burn_rate=ok"
echo "STATUS=ok"
