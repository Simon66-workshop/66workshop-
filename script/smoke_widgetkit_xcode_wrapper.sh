#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/mac/66TaskLight"
SPEC="$PACKAGE_DIR/project.yml"
APP_INFO="$PACKAGE_DIR/XcodeWrapper/AppInfo.plist"
APP_ENTITLEMENTS="$PACKAGE_DIR/WidgetKitScaffold/66TaskLightApp.entitlements"
WIDGET_ENTITLEMENTS="$PACKAGE_DIR/WidgetKitScaffold/66TaskLightWidgetExtension.entitlements"
WIDGET_INFO="$PACKAGE_DIR/WidgetKitScaffold/Info.plist"
WIDGET_SWIFT="$PACKAGE_DIR/WidgetKitScaffold/66TaskLightWidget.swift"

fail() {
  echo "smoke_widgetkit_xcode_wrapper: $*" >&2
  exit 1
}

[[ -f "$SPEC" ]] || fail "XcodeGen project.yml is missing"
[[ -f "$APP_INFO" ]] || fail "app Info.plist is missing"
[[ -f "$APP_ENTITLEMENTS" ]] || fail "app entitlements are missing"
[[ -f "$WIDGET_ENTITLEMENTS" ]] || fail "widget entitlements are missing"
[[ -f "$WIDGET_INFO" ]] || fail "widget Info.plist is missing"

rg -q "66TaskLightWidgetExtension" "$SPEC" || fail "widget extension target is missing"
rg -q "type: app-extension" "$SPEC" || fail "widget target must be an app extension"
rg -q "embed: true" "$SPEC" || fail "main app must embed widget extension"
rg -q "product: TaskLightCore" "$SPEC" || fail "Xcode wrapper must reuse TaskLightCore package product"
rg -q "CODE_SIGN_ENTITLEMENTS: WidgetKitScaffold/66TaskLightApp.entitlements" "$SPEC" || fail "main app App Group entitlements are not wired"
rg -q "CODE_SIGN_ENTITLEMENTS: WidgetKitScaffold/66TaskLightWidgetExtension.entitlements" "$SPEC" || fail "widget App Group entitlements are not wired"
rg -q "group.com.66tasklight.widget" "$APP_ENTITLEMENTS" "$WIDGET_ENTITLEMENTS" || fail "App Group id is not consistent"
rg -q "com.apple.widgetkit-extension" "$WIDGET_INFO" || fail "WidgetKit extension point is missing"
rg -q "@main" "$WIDGET_SWIFT" || fail "WidgetBundle entrypoint is missing"

if rg -n "auth\\.json|OPENAI_API_KEY|GITHUB_TOKEN|URLSession|curl" "$SPEC" "$APP_INFO" "$WIDGET_INFO" "$WIDGET_SWIFT" >/tmp/66tasklight-widgetkit-wrapper-risk.txt; then
  cat /tmp/66tasklight-widgetkit-wrapper-risk.txt
  fail "Widget wrapper scaffold must not introduce secrets or external API calls"
fi

echo "smoke_widgetkit_xcode_wrapper=ok"
echo "STATUS=ok"
