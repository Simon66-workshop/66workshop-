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
rg -q "struct CodexQuotaResetSnapshot" "$TYPES" || fail "Codex quota reset snapshot type is missing"
rg -q "struct CodexQuotaResetWindow" "$TYPES" || fail "Codex quota reset window type is missing"
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
rg -q "Codex Reset" "$RADAR" || fail "task radar must render Codex Reset"
rg -q "quotaResetSnapshot" "$VM" "$RADAR" || fail "quota reset snapshot helper is missing"
rg -q "manual_resets_available" "$TYPES" "$VM" "$RADAR" || fail "manual reset count must be surfaced"
rg -q "manual_reset_credits" "$TYPES" "$VM" "$RADAR" "$ROOT_DIR/script/state_projector.py" || fail "reset credit rows must be surfaced"
rg -q "manual_resets_next_expiry" "$TYPES" "$VM" "$ROOT_DIR/script/state_projector.py" || fail "reset credit next expiry must be surfaced"
rg -q "expires_at" "$TYPES" "$RADAR" "$ROOT_DIR/script/codex_quota_import.py" "$ROOT_DIR/script/state_projector.py" || fail "reset credit precise expiry time must be preserved"
rg -q "最迟有效期" "$RADAR" || fail "reset credit UI must label expiry as latest valid time"
rg -q "CodexQuotaResetCreditUIState" "$TYPES" "$RADAR" || fail "reset credit UI row type is missing"
rg -q "reset_at" "$TYPES" "$VM" "$ROOT_DIR/script/state_projector.py" || fail "quota reset_at must be preserved"
rg -q "validity_label" "$TYPES" "$VM" "$RADAR" || fail "quota window validity label must be surfaced"

if rg -n "global_status|lamp_status" "$STORE" "$VM" | rg "quotaBurnRateSnapshot|burnRateWindow|appendQuotaHistorySample|quotaHistory" >/tmp/66tasklight-quota-main-lamp.txt; then
  cat /tmp/66tasklight-quota-main-lamp.txt
  fail "quota burn-rate code must not change main lamp status"
fi

echo "smoke_quota_burn_rate=ok"
echo "STATUS=ok"
