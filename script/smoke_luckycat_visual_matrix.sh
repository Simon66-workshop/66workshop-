#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp"

fail() {
  echo "STATUS=fail"
  echo "reason=$1"
  exit 1
}

preview_data="$APP_DIR/Preview/LuckyCatPreviewData.swift"
matrix_view="$APP_DIR/Preview/LuckyCatVisualStateMatrixView.swift"

[ -f "$preview_data" ] || fail "LuckyCatPreviewData is missing"
[ -f "$matrix_view" ] || fail "LuckyCatVisualStateMatrixView is missing"

for scenario in idle running pending blocked done observed lowQuota quotaUnknown; do
  rg -q "id: \"$scenario\"" "$preview_data" \
    || fail "visual matrix scenario missing: $scenario"
done

rg -q "LuckyCatCompactView\\(viewModel: model\\)" "$matrix_view" \
  || fail "visual matrix must render compact cat"

rg -q "LuckyCatEdgeRailView\\(viewModel: model\\)" "$matrix_view" \
  || fail "visual matrix must render edge rail"

rg -q "LuckyCatVisualMatrixHostView" "$matrix_view" "$APP_DIR/TaskLightMenuBarController.swift" \
  || fail "visual matrix should open through a lightweight host shell"

rg -q "menuBarStatusTitle\\(\\)" "$matrix_view" \
  || fail "visual matrix must render menu bar status title"

rg -q "quotaIsCritical\\(\\)" "$matrix_view" \
  || fail "visual matrix must include low quota color path"

rg -q "TaskLightViewModel\\(previewUIState: scenario\\.uiState\\)" "$matrix_view" \
  || fail "visual matrix should construct cached models from scenario ui_state"

rg -q "init\\(previewUIState: TaskLightUIState\\)" "$APP_DIR/TaskLightViewModel.swift" \
  || fail "preview-only view model initializer is missing"

rg -q "@StateObject private var model: TaskLightViewModel" "$matrix_view" \
  || fail "visual matrix scenario cards should cache preview view models"

if rg -n "let model = previewModel|private func previewModel|TaskLightViewModel\\(\\)" "$matrix_view" >/tmp/66tasklight-visual-matrix-heavy-model.txt; then
  cat /tmp/66tasklight-visual-matrix-heavy-model.txt
  fail "visual matrix must not create fresh runtime view models during body rendering"
fi

rg -q "process_only_not_authoritative" "$preview_data" \
  || fail "visual matrix must include process-only ignored diagnostic fixture"

if rg -n "Image\\(|NSImage|\\.png|\\.jpg|\\.jpeg|screenshot|overlay.*reference" "$matrix_view" "$preview_data" >/tmp/66tasklight-visual-matrix-static-art.txt; then
  cat /tmp/66tasklight-visual-matrix-static-art.txt
  fail "visual matrix must not use static screenshots or reference art"
fi

echo "STATUS=ok"
