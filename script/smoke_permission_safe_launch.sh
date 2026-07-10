#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/script/build_and_run.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

python3 - "$BUILD_SCRIPT" <<'PY'
import re
import sys
from pathlib import Path

script = Path(sys.argv[1]).read_text(encoding="utf-8")

if 'REFRESH_DESKTOP_BUNDLE="${TASKLIGHT_REFRESH_DESKTOP_BUNDLE:-0}"' not in script:
    raise SystemExit("default desktop refresh must be disabled")

run_match = re.search(r'\n  run\)\n(?P<body>.*?)\n    ;;\n', script, re.S)
if not run_match:
    raise SystemExit("run mode not found")
if "refresh_desktop_bundle" in run_match.group("body"):
    raise SystemExit("run mode must not refresh Desktop app")

install_match = re.search(r'install_desktop_bundle\(\) \{\n(?P<body>.*?)\n\}', script, re.S)
if not install_match:
    raise SystemExit("install_desktop_bundle function not found")
install_body = install_match.group("body")
if "REFRESH_DESKTOP_BUNDLE=1 refresh_desktop_bundle" not in install_body:
    raise SystemExit("desktop install must explicitly opt into Desktop refresh")

if "--install-desktop|install-desktop|refresh-desktop)" not in script:
    raise SystemExit("explicit install-desktop mode not wired")
PY

echo "smoke_permission_safe_launch=ok"
