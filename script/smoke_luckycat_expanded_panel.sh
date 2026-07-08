#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp"

fail() {
  echo "STATUS=fail"
  echo "reason=$1"
  exit 1
}

view_model="$APP_DIR/TaskLightViewModel.swift"
panel="$APP_DIR/TaskLightPanelController.swift"
app_delegate="$APP_DIR/TaskLightAppDelegate.swift"
dashboard="$APP_DIR/Screens/LuckyCatExpandedDashboardView.swift"
budget="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightUIPerformanceBudget.swift"
build_script="$ROOT_DIR/script/build_and_run.sh"

rg -q "runExpandedPanelSelfTest" "$panel" \
  || fail "expanded panel runtime self-test hook is missing"

rg -q -- "--tasklight-expanded-panel-self-test" "$app_delegate" "$build_script" \
  || fail "expanded panel self-test launch argument is missing"

sed -n '/func sortedManagedTasks/,/^    func invalidManagedTasks/p' "$view_model" > /tmp/66tasklight-sorted-managed-tasks.txt
if rg -n "uiDisplayScope\\(" /tmp/66tasklight-sorted-managed-tasks.txt >/tmp/66tasklight-expanded-panel-n2-sort.txt; then
  cat /tmp/66tasklight-expanded-panel-n2-sort.txt
  fail "expanded dashboard task sorting must not call uiDisplayScope inside the comparator"
fi

rg -q "lhs\\.display_scope" /tmp/66tasklight-sorted-managed-tasks.txt \
  || fail "expanded dashboard should sort using TaskLightUITask display_scope directly"

rg -q "LuckyCatExpandedDashboardCacheBuilder" "$dashboard" \
  || fail "expanded dashboard should derive heavy task cache through a dedicated cache builder"

rg -q "DispatchQueue\\.global\\(qos: \\.userInitiated\\)" "$dashboard" \
  || fail "expanded dashboard task cache should be built off the main thread"

rg -q "managedTaskCacheLimit" "$dashboard" \
  || fail "expanded dashboard should maintain a paged managed task cache limit"

rg -q "expandedManagedTaskCachePageSize" "$budget" "$dashboard" \
  || fail "expanded dashboard should expose a managed task cache page size"

rg -q "expandedManagedTaskCacheHardLimit" "$budget" "$dashboard" \
  || fail "expanded dashboard should cap paged cache growth"

rg -q "Load next .* page" "$dashboard" \
  || fail "expanded dashboard should expose a paged load-more action"

if rg -n "cachedManagedTasks = viewModel\\.sortedManagedTasks\\(" "$dashboard" >/tmp/66tasklight-expanded-main-thread-sort.txt; then
  cat /tmp/66tasklight-expanded-main-thread-sort.txt
  fail "expanded dashboard must not sort managed tasks directly into @State on the main thread"
fi

sed -n '/func taskRadarActiveTasks()/,/^    func taskRadarObservedThreads()/p' "$view_model" > /tmp/66tasklight-radar-active-tasks.txt
if rg -n "sortedManagedTasks\\(|uiDisplayScope\\(" /tmp/66tasklight-radar-active-tasks.txt >/tmp/66tasklight-radar-active-heavy.txt; then
  cat /tmp/66tasklight-radar-active-heavy.txt
  fail "task radar active tasks should filter TaskLightUITask directly before sorting"
fi

echo "STATUS=ok"
