#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKLIGHT_TEST_RETENTION_SECONDS=120 "$ROOT_DIR/script/smoke_reliability_m38.sh" >/dev/null
TASKLIGHT_TEST_RETENTION_SECONDS=7 "$ROOT_DIR/script/smoke_reliability_m38.sh" >/dev/null
echo "smoke_signal_retention_time_boundary=ok"
