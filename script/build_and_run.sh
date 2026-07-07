#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="66TaskLight"
BUILD_TARGET="TaskLightApp"
BINARY_NAME="$BUILD_TARGET"
LEGACY_BINARY_NAME="66TaskLight"
BUNDLE_ID="com.local.66tasklight"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/mac/66TaskLight"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
RUNTIME_DIR="${TMPDIR:-/tmp}/66tasklight-runtime"
RUNTIME_BUNDLE="$RUNTIME_DIR/$APP_NAME.app"
DESKTOP_BUNDLE="$HOME/Desktop/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$BINARY_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ASSETS_DIR="$PACKAGE_DIR/AppAssets"

kill_existing() {
  pkill -x "$BINARY_NAME" >/dev/null 2>&1 || true
  pkill -x "$LEGACY_BINARY_NAME" >/dev/null 2>&1 || true
}

build_app() {
  (cd "$PACKAGE_DIR" && swift build)
}

stage_bundle() {
  local build_binary
  local build_bin_dir
  build_bin_dir="$(cd "$PACKAGE_DIR" && swift build --show-bin-path)"
  build_binary="$build_bin_dir/$BUILD_TARGET"
  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS"
  cp "$build_binary" "$APP_BINARY"
  mkdir -p "$APP_CONTENTS/Resources"
  if [ -d "$APP_ASSETS_DIR" ]; then
    cp -R "$APP_ASSETS_DIR"/. "$APP_CONTENTS/Resources/"
  fi
  chmod +x "$APP_BINARY"
  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$BINARY_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
  xattr -dr com.apple.quarantine "$APP_BUNDLE" >/dev/null 2>&1 || true
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
}

stage_runtime_bundle() {
  rm -rf "$RUNTIME_BUNDLE"
  mkdir -p "$RUNTIME_DIR"
  cp -R "$APP_BUNDLE" "$RUNTIME_BUNDLE"
}

refresh_desktop_bundle() {
  if [ -e "$DESKTOP_BUNDLE" ] || [ -L "$DESKTOP_BUNDLE" ]; then
    if ! rm -rf "$DESKTOP_BUNDLE" >/dev/null 2>&1; then
      echo "warning: could not replace desktop app at $DESKTOP_BUNDLE" >&2
      return 0
    fi
  fi

  if ! cp -R "$RUNTIME_BUNDLE" "$DESKTOP_BUNDLE" >/dev/null 2>&1; then
    echo "warning: could not install desktop app at $DESKTOP_BUNDLE" >&2
    return 0
  fi
}

open_app() {
  /usr/bin/open -n "$RUNTIME_BUNDLE"
}

launch_edge_toggle_self_test() {
  local state_dir="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
  local result_path="$state_dir/edge_toggle_self_test.json"
  rm -f "$result_path"
  /usr/bin/open -n "$RUNTIME_BUNDLE" --args --tasklight-edge-self-test
  for _ in $(seq 1 100); do
    if [ -s "$result_path" ]; then
      python3 - "$result_path" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))

def emit(key, value):
    print(f"{key}={value}")

emit("edge_toggle_self_test_path", path)
emit("edge_toggle_self_test_status", payload.get("status", "missing"))
emit("collapse_apply_ms", payload.get("collapse_apply_ms", "missing"))
emit("restore_apply_ms", payload.get("restore_apply_ms", "missing"))
emit("transition_duration_ms", payload.get("transition_duration_ms", "missing"))
emit("compact_drag_pass", payload.get("compact_drag_pass", "missing"))
emit("body_click_pass", payload.get("body_click_pass", "missing"))
emit("click_path_collapsed", payload.get("click_path_collapsed", "missing"))
emit("collapsed_pass", payload.get("collapsed_pass", "missing"))
emit("collapsed_alpha_pass", payload.get("collapsed_alpha_pass", "missing"))
emit("edge_drag_pass", payload.get("edge_drag_pass", "missing"))
emit("restored_pass", payload.get("restored_pass", "missing"))
emit("restored_alpha_pass", payload.get("restored_alpha_pass", "missing"))
emit("restored_from_moved_edge_pass", payload.get("restored_from_moved_edge_pass", "missing"))
emit("compact_alpha", payload.get("compact_alpha", "missing"))
emit("edge_alpha", payload.get("edge_alpha", "missing"))
emit("compact_frame", payload.get("compact_frame", {}))
emit("edge_frame", payload.get("edge_frame", {}))
emit("expected_restored_frame", payload.get("expected_restored_frame", {}))

if payload.get("status") != "ok":
    raise SystemExit(1)

if payload.get("click_path_collapsed") is not True:
    raise SystemExit("click_path_collapsed was not true")

if payload.get("compact_drag_pass") is not True:
    raise SystemExit("compact_drag_pass was not true")

if payload.get("body_click_pass") is not True:
    raise SystemExit("body_click_pass was not true")

if payload.get("edge_drag_pass") is not True:
    raise SystemExit("edge_drag_pass was not true")

if payload.get("restored_from_moved_edge_pass") is not True:
    raise SystemExit("restored_from_moved_edge_pass was not true")

if float(payload.get("collapse_apply_ms", 9999)) > 50:
    raise SystemExit("collapse_apply_ms exceeded 50ms")

if float(payload.get("restore_apply_ms", 9999)) > 50:
    raise SystemExit("restore_apply_ms exceeded 50ms")

if float(payload.get("transition_duration_ms", 9999)) > 120:
    raise SystemExit("transition_duration_ms exceeded 120ms")
PY
      return
    fi
    sleep 0.2
  done
  echo "edge_toggle_self_test_status=timeout"
  pgrep -fl "$BINARY_NAME" || true
  tail -40 "$state_dir/startup_trace.log" 2>/dev/null || true
  return 1
}

launch_logs() {
  open_app
  /usr/bin/log stream --info --style compact --predicate "process == \"$BINARY_NAME\""
}

launch_telemetry() {
  open_app
  /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
}

verify_launch() {
  open_app
  for _ in $(seq 1 20); do
    if pgrep -x "$BINARY_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  pgrep -x "$BINARY_NAME" >/dev/null
}

json_status() {
  local path="$1"
  local empty_ok="${2:-missing_empty_ok}"
  python3 - "$path" "$empty_ok" <<'PY'
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
empty_ok = sys.argv[2]

if not path.exists() or path.stat().st_size == 0:
    print(empty_ok)
    raise SystemExit(0)

try:
    payload = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    print("unreadable_error")
    raise SystemExit(0)

if isinstance(payload, dict):
    print("readable")
else:
    print("unreadable_error")
PY
}

report_verify_context() {
  local state_dir="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
  local state_json="$state_dir/state.json"
  local ui_state="$state_dir/ui_state.json"
  local observations_state="$state_dir/observations_state.json"
  local projector_health="$state_dir/state_projector_health.json"

  echo "bundle_path=$APP_BUNDLE"
  echo "launch_bundle_path=$RUNTIME_BUNDLE"
  if pgrep -x "$BINARY_NAME" >/dev/null 2>&1; then
    echo "app_process_status=running"
  else
    echo "app_process_status=not_running"
  fi
  echo "state_dir=$state_dir"
  echo "state_json_status=$(json_status "$state_json")"
  echo "ui_state_status=$(json_status "$ui_state")"
  echo "state_projector_health_status=$(json_status "$projector_health" "missing_empty_ok")"
  echo "observations_state_status=$(json_status "$observations_state")"
  TASKLIGHT_STATE_DIR="$state_dir" "$ROOT_DIR/script/check_observer.sh"
  TASKLIGHT_STATE_DIR="$state_dir" "$ROOT_DIR/script/check_state_projector.sh"
  echo "swift_build=success"
}

case "$MODE" in
  run)
    kill_existing
    build_app
    stage_bundle
    stage_runtime_bundle
    refresh_desktop_bundle
    open_app
    ;;
  --debug|debug)
    kill_existing
    build_app
    stage_bundle
    stage_runtime_bundle
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    kill_existing
    build_app
    stage_bundle
    stage_runtime_bundle
    launch_logs
    ;;
  --telemetry|telemetry)
    kill_existing
    build_app
    stage_bundle
    stage_runtime_bundle
    launch_telemetry
    ;;
  --verify|verify)
    kill_existing
    build_app
    stage_bundle
    stage_runtime_bundle
    verify_launch
    report_verify_context
    ;;
  --edge-toggle-self-test|edge-toggle-self-test)
    kill_existing
    build_app
    stage_bundle
    stage_runtime_bundle
    launch_edge_toggle_self_test
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--edge-toggle-self-test]" >&2
    exit 2
    ;;
esac
