#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

set +e
output="$("$ROOT_DIR/script/build_and_run.sh" --edge-toggle-self-test 2>&1)"
exit_code=$?
set -e
printf '%s\n' "$output"

if [ "$exit_code" -ne 0 ]; then
  echo "STATUS=fail"
  echo "reason=edge toggle runtime self-test command failed"
  exit "$exit_code"
fi

if ! grep -q '^edge_toggle_self_test_status=ok$' <<<"$output"; then
  echo "STATUS=fail"
  echo "reason=edge toggle runtime self-test did not report ok"
  exit 1
fi

if ! grep -q '^click_path_collapsed=True$' <<<"$output"; then
  echo "STATUS=fail"
  echo "reason=edge toggle runtime self-test did not exercise the compact click handler"
  exit 1
fi

if ! grep -q '^compact_drag_pass=True$' <<<"$output"; then
  echo "STATUS=fail"
  echo "reason=edge toggle runtime self-test did not prove compact drag stays compact"
  exit 1
fi

if ! grep -q '^body_click_pass=True$' <<<"$output"; then
  echo "STATUS=fail"
  echo "reason=edge toggle runtime self-test did not prove compact body click stays compact"
  exit 1
fi

if ! grep -q '^collapsed_pass=True$' <<<"$output"; then
  echo "STATUS=fail"
  echo "reason=edge toggle runtime self-test did not prove capsule state"
  exit 1
fi

if ! grep -q '^collapsed_alpha_pass=True$' <<<"$output"; then
  echo "STATUS=fail"
  echo "reason=edge toggle runtime self-test did not prove visible capsule alpha"
  exit 1
fi

if ! grep -q '^collapsed_anchored_from_compact_pass=True$' <<<"$output"; then
  echo "STATUS=fail"
  echo "reason=edge toggle runtime self-test did not prove capsule anchors from the current cat frame"
  exit 1
fi

if ! grep -q '^edge_drag_pass=True$' <<<"$output"; then
  echo "STATUS=fail"
  echo "reason=edge toggle runtime self-test did not prove rail drag stays rail"
  exit 1
fi

if ! grep -q '^restored_pass=True$' <<<"$output"; then
  echo "STATUS=fail"
  echo "reason=edge toggle runtime self-test did not prove restored cat state"
  exit 1
fi

if ! grep -q '^restored_alpha_pass=True$' <<<"$output"; then
  echo "STATUS=fail"
  echo "reason=edge toggle runtime self-test did not prove visible restored cat alpha"
  exit 1
fi

if ! grep -q '^restored_from_moved_edge_pass=True$' <<<"$output"; then
  echo "STATUS=fail"
  echo "reason=edge toggle runtime self-test did not prove restore anchors to moved capsule"
  exit 1
fi

echo "smoke_luckycat_edge_toggle_runtime=ok"
echo "STATUS=ok"
