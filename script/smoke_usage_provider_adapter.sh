#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TYPES="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift"
VM="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift"
RADAR="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/Screens/TaskRadarPopoverView.swift"
DOC="$ROOT_DIR/docs/USAGE_PROVIDER_ADAPTERS.md"

fail() {
  echo "smoke_usage_provider_adapter: $*" >&2
  exit 1
}

rg -q "protocol UsageProviderAdapter" "$TYPES" || fail "UsageProviderAdapter is missing"
rg -q "struct CodexUsageProviderAdapter" "$TYPES" || fail "Codex provider adapter is missing"
rg -q "DisabledUsageProviderAdapter" "$TYPES" "$VM" || fail "disabled provider placeholders are missing"
rg -q "usageProviderSnapshots" "$VM" "$RADAR" || fail "provider snapshots are not surfaced"
rg -q "diagnostic_only" "$TYPES" || fail "provider snapshots must be diagnostic-only"
rg -q "Do not read.*auth\\.json" "$DOC" || fail "provider safety doc must forbid auth reads"
rg -q "Do not call external provider APIs" "$DOC" || fail "provider safety doc must forbid default external calls"
rg -q "disabled placeholder" "$DOC" || fail "provider doc must mark non-Codex providers disabled"

if rg -n "URLSession|curl|auth\\.json|OPENAI_API_KEY|GITHUB_TOKEN|COPILOT|CLAUDE" "$TYPES" "$VM" "$RADAR" >/tmp/66tasklight-provider-risk.txt; then
  cat /tmp/66tasklight-provider-risk.txt
  fail "provider adapter v1 must not read secrets or call external APIs"
fi

if rg -n "global_status.*provider|lamp_status.*provider|provider.*global_status|provider.*lamp_status" "$TYPES" "$VM" "$RADAR" >/tmp/66tasklight-provider-main-lamp-risk.txt; then
  cat /tmp/66tasklight-provider-main-lamp-risk.txt
  fail "provider adapter must not affect main lamp"
fi

echo "smoke_usage_provider_adapter=ok"
echo "STATUS=ok"
