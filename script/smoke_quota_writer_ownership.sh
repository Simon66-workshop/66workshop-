#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-quota-owner-XXXXXX")"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

python3 - "$ROOT_DIR" "$STATE_DIR" <<'PY'
import os
import sys
from datetime import datetime
from pathlib import Path

root_dir = Path(sys.argv[1])
state_dir = Path(sys.argv[2])
sys.path.insert(0, str(root_dir / "script"))

import state_projector as projector

plist = state_dir / "quota-watcher.plist"
plist.write_text("<plist/>", encoding="utf-8")
projector.DEFAULT_STATE_DIR = state_dir
os.environ["TASKLIGHT_QUOTA_WATCHER_PLIST"] = str(plist)

assert projector.production_quota_watcher_installed(state_dir)

health = state_dir / "quota_probe_health.json"
health.write_text(
    '{"writer":"quota_watcher","poll_seconds":10,"request_timeout_seconds":5,"last_probe_at":"%s"}'
    % datetime.now().astimezone().replace(microsecond=0).isoformat(),
    encoding="utf-8",
)
assert projector.quota_watcher_owns_snapshot(state_dir, datetime.now().timestamp())
PY

echo "smoke_quota_writer_ownership: ok"
