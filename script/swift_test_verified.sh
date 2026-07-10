#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/mac/66TaskLight"
LOG_FILE="${TASKLIGHT_SWIFT_TEST_LOG_PATH:-/tmp/66tasklight-swift-test.log}"

cd "$PACKAGE_DIR"
swift test --enable-swift-testing 2>&1 | tee "$LOG_FILE"

# Command Line Tools can build Swift Testing bundles but does not ship xctest.
# Run the same shared suite through its executable entry point so zero executed
# tests can never be reported as a green check.
runner_output="$(swift run TaskLightTestRunner 2>&1)"
printf '%s\n' "$runner_output"
grep -Eq 'Test run with [1-9][0-9]* tests?.* passed' <<<"$runner_output"

echo "swift_test_verified=ok"
