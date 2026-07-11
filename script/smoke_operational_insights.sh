#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSIGHTS="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightOperationalInsights.swift"
RADAR="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/Screens/TaskRadarPopoverView.swift"
VM="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift"

fail() {
  echo "smoke_operational_insights: $*" >&2
  exit 1
}

for type in TaskLightStatusExplanation WorkspaceRepairQueueItem QuotaCalendarEntry TaskLightProviderOptIn; do
  rg -q "$type" "$INSIGHTS" || fail "$type is missing"
done
rg -q "process_only_not_authoritative" "$INSIGHTS" || fail "process-only explanation is missing"
rg -q "multiple_writers" "$INSIGHTS" || fail "multiple writer explanation is missing"
rg -q "Manual Trust" "$RADAR" || fail "repair queue must preserve manual trust"
rg -q "Quota Calendar" "$RADAR" || fail "quota calendar is not visible in the radar"
rg -q "Why This Status" "$RADAR" || fail "status explainer is not visible in the radar"
rg -q "explicit_user_opt_in" "$INSIGHTS" "$VM" "$ROOT_DIR/script/tasklight_provider_plugins.py" || fail "external provider opt-in is incomplete"

if rg -n "global_status.*quota|lamp_status.*quota|quota.*global_status|quota.*lamp_status" "$INSIGHTS" "$VM" "$RADAR" >/tmp/66tasklight-insight-lamp-risk.txt; then
  cat /tmp/66tasklight-insight-lamp-risk.txt
  fail "operational insights must not change the main lamp"
fi

echo "smoke_operational_insights=ok"
echo "STATUS=ok"
