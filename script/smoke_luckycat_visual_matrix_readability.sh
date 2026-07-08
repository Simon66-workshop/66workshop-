#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREVIEW="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/Preview/LuckyCatPreviewData.swift"
MATRIX="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/Preview/LuckyCatVisualStateMatrixView.swift"

fail() {
  echo "STATUS=fail"
  echo "reason=$1"
  exit 1
}

for scenario in idle running pending blocked done observed lowQuota quotaUnknown oldWriter multipleProjector processOnly; do
  rg -q "id: \"$scenario\"" "$PREVIEW" || fail "visual matrix scenario missing: $scenario"
done

for label in "浅背景" "暗背景可读性" "复杂网页背景" "低 quota 红字" "Pending 黄球"; do
  rg -q "$label" "$MATRIX" || fail "readability scenario missing: $label"
done

rg -q "胶囊玻璃" "$MATRIX" || fail "visual matrix must label edge rail as a glass capsule preview"
rg -q "previewSurfaceFill" "$MATRIX" || fail "visual matrix should use tokenized preview surface fills"
rg -q "previewSurfaceEnvironment" "$MATRIX" || fail "visual matrix should render a glass preview environment"

if rg -n "Color\\.black|NSColor\\.black|\\.fill\\([^\\n]*black|#000000|#000" "$MATRIX" >/tmp/66tasklight-visual-matrix-black-surface.txt; then
  cat /tmp/66tasklight-visual-matrix-black-surface.txt
  fail "visual matrix must not use black preview surfaces for the glass capsule"
fi

rg -q "Quota Pace" "$MATRIX" || fail "visual matrix must include quota pace summary"
rg -q "Hooks Doctor" "$MATRIX" || fail "visual matrix must include hooks doctor badge"
rg -q "writerStatus: \"old_writer\"" "$PREVIEW" || fail "old writer fixture must be explicit"
rg -q "writerStatus: \"multiple_writers\"" "$PREVIEW" || fail "multiple projector fixture must be explicit"
rg -q "process_only_not_authoritative" "$PREVIEW" || fail "process-only fixture must be ignored diagnostic"

if rg -n "Image\\(|NSImage|\\.png|\\.jpg|\\.jpeg|screenshot|overlay.*reference" "$MATRIX" "$PREVIEW" >/tmp/66tasklight-readable-static-art.txt; then
  cat /tmp/66tasklight-readable-static-art.txt
  fail "readability matrix must not use static screenshots or overlays"
fi

echo "smoke_luckycat_visual_matrix_readability=ok"
echo "STATUS=ok"
