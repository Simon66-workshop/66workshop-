#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/script/build_and_run.sh" --expanded-panel-self-test

python3 - <<'PY'
import json
import pathlib
import sys

path = pathlib.Path.home() / ".66tasklight" / "expanded_panel_self_test.json"
payload = json.loads(path.read_text())
delay = payload.get("main_queue_probe_delay_ms", 9999)
responsive = payload.get("main_queue_responsive", False)
if payload.get("status") != "ok" or not responsive or delay > 160:
    print("STATUS=fail")
    print(f"reason=expanded panel main queue delayed: {delay}ms")
    sys.exit(1)
PY

echo "STATUS=ok"
