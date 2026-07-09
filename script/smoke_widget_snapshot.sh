#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TYPES="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift"
STORE="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightStore.swift"
VM="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift"
BUILD_SCRIPT="$ROOT_DIR/script/build_and_run.sh"
SCAFFOLD="$ROOT_DIR/mac/66TaskLight/WidgetKitScaffold/66TaskLightWidget.swift"
APP_ENTITLEMENTS="$ROOT_DIR/mac/66TaskLight/WidgetKitScaffold/66TaskLightApp.entitlements"
WIDGET_ENTITLEMENTS="$ROOT_DIR/mac/66TaskLight/WidgetKitScaffold/66TaskLightWidgetExtension.entitlements"

fail() {
  echo "smoke_widget_snapshot: $*" >&2
  exit 1
}

rg -q "struct TaskLightWidgetSnapshot" "$TYPES" || fail "TaskLightWidgetSnapshot is missing"
rg -q "widgetSnapshotURL" "$TYPES" "$STORE" || fail "widget snapshot path is not wired"
rg -q "saveWidgetSnapshot" "$STORE" "$VM" || fail "app does not export widget snapshot"
rg -q "WidgetKit" "$SCAFFOLD" || fail "WidgetKit scaffold is missing"
rg -q "TimelineProvider" "$SCAFFOLD" || fail "Widget timeline provider scaffold is missing"
rg -q "TaskLightWidgetBridge" "$TYPES" "$STORE" "$VM" "$SCAFFOLD" || fail "shared widget bridge is missing"
rg -q "group.com.66tasklight.widget" "$TYPES" "$APP_ENTITLEMENTS" "$WIDGET_ENTITLEMENTS" || fail "App Group is not declared consistently"
rg -q "containerURL\\(forSecurityApplicationGroupIdentifier: appGroupID\\)" "$TYPES" || fail "app group shared container path is not wired"
rg -q "loadWidgetSnapshotFromAppGroup" "$STORE" "$SCAFFOLD" || fail "widget shared snapshot read path is not wired"
rg -q "reloadTimelines\\(ofKind: TaskLightWidgetBridge.widgetKind\\)" "$VM" || fail "WidgetKit timeline reload is not wired"
rg -q "hasPrefix\\(\"--tasklight-\"\\)" "$STORE" "$VM" || fail "runtime self-tests must skip widget system side effects"
rg -q -- "--entitlements" "$BUILD_SCRIPT" || fail "app bundle signing does not include App Group entitlements"
rg -q "APP_ENTITLEMENTS" "$BUILD_SCRIPT" || fail "build script does not reference app entitlements"

if rg -n "\\b(prompt|response|authorization|credential|secret)\\b|auth\\.json|raw_log|raw body" "$TYPES" "$STORE" "$VM" "$SCAFFOLD" >/tmp/66tasklight-widget-sensitive.txt; then
  cat /tmp/66tasklight-widget-sensitive.txt
  fail "widget snapshot path must stay sanitized"
fi

echo "smoke_widget_snapshot=ok"
echo "STATUS=ok"
