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
REFRESH_DESKTOP_BUNDLE="${TASKLIGHT_REFRESH_DESKTOP_BUNDLE:-0}"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$BINARY_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ASSETS_DIR="$PACKAGE_DIR/AppAssets"
APP_ENTITLEMENTS="$PACKAGE_DIR/WidgetKitScaffold/66TaskLightApp.entitlements"

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
  if [ -f "$APP_ENTITLEMENTS" ]; then
    codesign --force --deep --sign - --entitlements "$APP_ENTITLEMENTS" "$APP_BUNDLE" >/dev/null
  else
    codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
  fi
}

stage_runtime_bundle() {
  rm -rf "$RUNTIME_BUNDLE"
  mkdir -p "$RUNTIME_DIR"
  cp -R "$APP_BUNDLE" "$RUNTIME_BUNDLE"
}

refresh_desktop_bundle() {
  if [ "$REFRESH_DESKTOP_BUNDLE" != "1" ]; then
    return 0
  fi

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

install_desktop_bundle() {
  build_app
  stage_bundle
  stage_runtime_bundle
  REFRESH_DESKTOP_BUNDLE=1 refresh_desktop_bundle
  echo "desktop_bundle_path=$DESKTOP_BUNDLE"
  echo "desktop_bundle_status=updated"
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
emit("collapsed_anchored_from_compact_pass", payload.get("collapsed_anchored_from_compact_pass", "missing"))
emit("edge_drag_pass", payload.get("edge_drag_pass", "missing"))
emit("edge_single_click_restore_pass", payload.get("edge_single_click_restore_pass", "missing"))
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

if payload.get("edge_single_click_restore_pass") is not True:
    raise SystemExit("edge_single_click_restore_pass was not true")

if payload.get("collapsed_anchored_from_compact_pass") is not True:
    raise SystemExit("collapsed_anchored_from_compact_pass was not true")

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

launch_visual_matrix_self_test() {
  local state_dir="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
  local result_path="$state_dir/visual_matrix_self_test.json"
  rm -f "$result_path"
  /usr/bin/open -n "$RUNTIME_BUNDLE" --args --tasklight-visual-matrix-self-test
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

emit("visual_matrix_self_test_path", path)
emit("visual_matrix_self_test_status", payload.get("status", "missing"))
emit("visual_matrix_visible", payload.get("visible", "missing"))
emit("visual_matrix_key", payload.get("key", "missing"))
emit("visual_matrix_title", payload.get("title", "missing"))
emit("visual_matrix_open_apply_ms", payload.get("open_apply_ms", "missing"))
emit("visual_matrix_main_queue_probe_delay_ms", payload.get("main_queue_probe_delay_ms", "missing"))
emit("visual_matrix_main_queue_responsive", payload.get("main_queue_responsive", "missing"))
emit("visual_matrix_frame", payload.get("frame", {}))

if payload.get("status") != "ok":
    raise SystemExit(1)

if payload.get("visible") is not True:
    raise SystemExit("visual matrix window was not visible")

if payload.get("title") != "66TaskLight 视觉状态矩阵":
    raise SystemExit("visual matrix window title mismatch")

frame = payload.get("frame") or {}
if float(frame.get("width", 0)) < 820 or float(frame.get("height", 0)) < 640:
    raise SystemExit("visual matrix window frame too small")

if float(payload.get("open_apply_ms", 9999)) > 500:
    raise SystemExit("visual matrix open_apply_ms exceeded 500ms")

if payload.get("main_queue_responsive") is not True:
    raise SystemExit("visual matrix progressive render blocked the main queue")

if float(payload.get("main_queue_probe_delay_ms", 9999)) > 160:
    raise SystemExit("visual matrix main queue probe exceeded 160ms")
PY
      return
    fi
    sleep 0.2
  done
  echo "visual_matrix_self_test_status=timeout"
  pgrep -fl "$BINARY_NAME" || true
  tail -40 "$state_dir/startup_trace.log" 2>/dev/null || true
  tail -40 "$state_dir/menu_bar_actions.log" 2>/dev/null || true
  return 1
}

launch_menu_bar_self_test() {
  local state_dir="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
  local result_path="$state_dir/menu_bar_self_test.json"
  rm -f "$result_path"
  /usr/bin/open -n "$RUNTIME_BUNDLE" --args --tasklight-menu-bar-self-test
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

emit("menu_bar_self_test_path", path)
emit("menu_bar_self_test_status", payload.get("status", "missing"))
emit("menu_bar_status_button_ready", payload.get("status_button_ready", "missing"))
emit("menu_bar_popover_content_ready", payload.get("popover_content_ready", "missing"))
emit("menu_bar_expanded_open_title_ready", payload.get("expanded_open_title_ready", "missing"))
emit("menu_bar_expanded_close_title_ready", payload.get("expanded_close_title_ready", "missing"))
emit("menu_bar_expanded_toggle_closed", payload.get("expanded_toggle_closed", "missing"))
emit("menu_bar_matrix_menu_action_ready", payload.get("matrix_menu_action_ready", "missing"))
emit("menu_bar_matrix_open_title_ready", payload.get("matrix_open_title_ready", "missing"))
emit("menu_bar_matrix_close_title_ready", payload.get("matrix_close_title_ready", "missing"))
emit("menu_bar_matrix_menu_action_visible", payload.get("matrix_menu_action_visible", "missing"))
emit("menu_bar_matrix_toggle_closed", payload.get("matrix_toggle_closed", "missing"))
emit("menu_bar_hooks_doctor_deferred_after_menu", payload.get("hooks_doctor_deferred_after_menu", "missing"))
emit("menu_bar_hooks_doctor_shown_after_menu_close", payload.get("hooks_doctor_shown_after_menu_close", "missing"))
emit("menu_bar_hooks_doctor_survives_status_refresh", payload.get("hooks_doctor_survives_status_refresh", "missing"))
emit("menu_bar_hooks_doctor_apply_ms", payload.get("hooks_doctor_apply_ms", "missing"))
emit("menu_bar_task_radar_controller_ms", payload.get("task_radar_controller_ms", "missing"))
emit("menu_bar_task_radar_frame_ms", payload.get("task_radar_frame_ms", "missing"))
emit("menu_bar_task_radar_show_ms", payload.get("task_radar_show_ms", "missing"))
emit("menu_bar_task_radar_order_ms", payload.get("task_radar_order_ms", "missing"))
emit("menu_bar_task_radar_total_ms", payload.get("task_radar_total_ms", "missing"))
emit("menu_bar_title", payload.get("menu_title", "missing"))
emit("menu_bar_open_apply_ms", payload.get("open_apply_ms", "missing"))

if payload.get("status") != "ok":
    raise SystemExit(1)

if payload.get("status_button_ready") is not True:
    raise SystemExit("menu bar status button action was not ready")

if payload.get("popover_content_ready") is not True:
    raise SystemExit("menu bar popover content was not ready")

if payload.get("expanded_open_title_ready") is not True:
    raise SystemExit("expanded panel open title/action was not ready")

if payload.get("expanded_close_title_ready") is not True:
    raise SystemExit("expanded panel close title/action was not ready")

if payload.get("expanded_toggle_closed") is not True:
    raise SystemExit("expanded panel toggle did not close the panel")

if payload.get("matrix_menu_action_ready") is not True:
    raise SystemExit("visual matrix menu action was not wired")

if payload.get("matrix_open_title_ready") is not True:
    raise SystemExit("visual matrix open title/action was not ready")

if payload.get("matrix_close_title_ready") is not True:
    raise SystemExit("visual matrix close title/action was not ready")

if payload.get("matrix_menu_action_visible") is not True:
    raise SystemExit("visual matrix menu action did not show the window")

if payload.get("matrix_toggle_closed") is not True:
    raise SystemExit("visual matrix toggle did not close the window")

if payload.get("hooks_doctor_deferred_after_menu") is not True:
    raise SystemExit("hooks doctor open action was not deferred until menu close")

if payload.get("hooks_doctor_shown_after_menu_close") is not True:
    raise SystemExit("hooks doctor did not show after native menu close")

if payload.get("hooks_doctor_survives_status_refresh") is not True:
    raise SystemExit("hooks doctor popover was closed by status/menu title refresh")

if float(payload.get("hooks_doctor_apply_ms", 9999)) > 150:
    raise SystemExit("hooks doctor open exceeded 150ms")

if not str(payload.get("menu_title", "")).strip():
    raise SystemExit("menu bar title was empty")
PY
      return
    fi
    sleep 0.2
  done
  echo "menu_bar_self_test_status=timeout"
  pgrep -fl "$BINARY_NAME" || true
  tail -40 "$state_dir/startup_trace.log" 2>/dev/null || true
  return 1
}

launch_expanded_panel_self_test() {
  local state_dir="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
  local result_path="$state_dir/expanded_panel_self_test.json"
  rm -f "$result_path"
  /usr/bin/open -n "$RUNTIME_BUNDLE" --args --tasklight-expanded-panel-self-test
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

emit("expanded_panel_self_test_path", path)
emit("expanded_panel_self_test_status", payload.get("status", "missing"))
emit("expanded_panel_visible", payload.get("visible", "missing"))
emit("expanded_panel_expanded", payload.get("expanded", "missing"))
emit("expanded_panel_content_expanded", payload.get("content_expanded", "missing"))
emit("expanded_panel_managed_task_count", payload.get("managed_task_count", "missing"))
emit("expanded_panel_open_apply_ms", payload.get("open_apply_ms", "missing"))
emit("expanded_panel_visible_apply_ms", payload.get("visible_apply_ms", "missing"))
emit("expanded_panel_main_queue_probe_delay_ms", payload.get("main_queue_probe_delay_ms", "missing"))
emit("expanded_panel_main_queue_responsive", payload.get("main_queue_responsive", "missing"))
emit("expanded_panel_frame", payload.get("frame", {}))

if payload.get("status") != "ok":
    raise SystemExit(1)

if payload.get("visible") is not True:
    raise SystemExit("expanded panel was not visible")

if payload.get("expanded") is not True:
    raise SystemExit("view model expanded was not true")

if payload.get("content_expanded") is not True:
    raise SystemExit("expanded content was not activated")

if float(payload.get("open_apply_ms", 9999)) > 300:
    raise SystemExit("expanded panel open_apply_ms exceeded 300ms")
PY
      return
    fi
    sleep 0.2
  done
  echo "expanded_panel_self_test_status=timeout"
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
    open_app
    ;;
  --install-desktop|install-desktop|refresh-desktop)
    install_desktop_bundle
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
  --visual-matrix-self-test|visual-matrix-self-test)
    kill_existing
    build_app
    stage_bundle
    stage_runtime_bundle
    launch_visual_matrix_self_test
    ;;
  --menu-bar-self-test|menu-bar-self-test)
    kill_existing
    build_app
    stage_bundle
    stage_runtime_bundle
    launch_menu_bar_self_test
    ;;
  --expanded-panel-self-test|expanded-panel-self-test)
    kill_existing
    build_app
    stage_bundle
    stage_runtime_bundle
    launch_expanded_panel_self_test
    ;;
  *)
    echo "usage: $0 [run|install-desktop|--debug|--logs|--telemetry|--verify|--edge-toggle-self-test|--visual-matrix-self-test|--menu-bar-self-test|--expanded-panel-self-test]" >&2
    exit 2
    ;;
esac
