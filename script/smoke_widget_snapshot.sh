#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TYPES="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift"
STORE="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightStore.swift"
VM="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift"
SCAFFOLD="$ROOT_DIR/mac/66TaskLight/WidgetKitScaffold/66TaskLightWidget.swift"

fail() {
  echo "smoke_widget_snapshot: $*" >&2
  exit 1
}

rg -q "struct TaskLightWidgetSnapshot" "$TYPES" || fail "TaskLightWidgetSnapshot is missing"
rg -q "widgetSnapshotURL" "$TYPES" "$STORE" || fail "widget snapshot path is not wired"
rg -q "saveWidgetSnapshot" "$STORE" "$VM" || fail "app does not export widget snapshot"
rg -q "WidgetKit" "$SCAFFOLD" || fail "WidgetKit scaffold is missing"
rg -q "TimelineProvider" "$SCAFFOLD" || fail "Widget timeline provider scaffold is missing"

if rg -n "\\b(prompt|response|authorization|credential|secret)\\b|auth\\.json|raw_log|raw body" "$TYPES" "$STORE" "$VM" "$SCAFFOLD" >/tmp/66tasklight-widget-sensitive.txt; then
  cat /tmp/66tasklight-widget-sensitive.txt
  fail "widget snapshot path must stay sanitized"
fi

echo "smoke_widget_snapshot=ok"
echo "STATUS=ok"
