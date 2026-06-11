#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="66TaskLight"
BINARY_NAME="66TaskLight"
BUILD_TARGET="TaskLightApp"
BUNDLE_ID="com.local.66tasklight"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/mac/66TaskLight"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
RUNTIME_DIR="${TMPDIR:-/tmp}/66tasklight-runtime"
RUNTIME_BUNDLE="$RUNTIME_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$BINARY_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ASSETS_DIR="$PACKAGE_DIR/AppAssets"

kill_existing() {
  pkill -x "$BINARY_NAME" >/dev/null 2>&1 || true
  pkill -x "$BUILD_TARGET" >/dev/null 2>&1 || true
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
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

stage_runtime_bundle() {
  rm -rf "$RUNTIME_BUNDLE"
  mkdir -p "$RUNTIME_DIR"
  cp -R "$APP_BUNDLE" "$RUNTIME_BUNDLE"
}

open_app() {
  /usr/bin/open -n "$RUNTIME_BUNDLE"
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
  local observations_state="$state_dir/observations_state.json"

  echo "bundle_path=$APP_BUNDLE"
  echo "launch_bundle_path=$RUNTIME_BUNDLE"
  if pgrep -x "$BINARY_NAME" >/dev/null 2>&1; then
    echo "app_process_status=running"
  else
    echo "app_process_status=not_running"
  fi
  echo "state_dir=$state_dir"
  echo "state_json_status=$(json_status "$state_json")"
  echo "observations_state_status=$(json_status "$observations_state")"
  TASKLIGHT_STATE_DIR="$state_dir" "$ROOT_DIR/script/check_observer.sh"
  echo "swift_build=success"
}

case "$MODE" in
  run)
    kill_existing
    build_app
    stage_bundle
    stage_runtime_bundle
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
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
