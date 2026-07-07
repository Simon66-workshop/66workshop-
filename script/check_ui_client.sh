#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
CLIENT_DIR="${TASKLIGHT_UI_CLIENTS_DIR:-$STATE_DIR/ui_clients}"
DESKTOP_APP="${TASKLIGHT_DESKTOP_APP_PATH:-$HOME/Desktop/66TaskLight.app}"

_client_output="$(python3 - "$CLIENT_DIR" "$DESKTOP_APP" <<'PY'
import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path

client_dir = Path(sys.argv[1]).expanduser()
desktop_app = Path(sys.argv[2]).expanduser()

def parse_ts(value):
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except Exception:
        return 0

def load_clients():
    clients = []
    if client_dir.exists():
        for path in client_dir.glob("*.json"):
            try:
                payload = json.loads(path.read_text(encoding="utf-8"))
            except Exception:
                continue
            payload["file_path"] = str(path)
            clients.append(payload)
    return sorted(clients, key=lambda item: parse_ts(item.get("updated_at") or item.get("started_at")), reverse=True)

def pids():
    values = []
    for process_name in ("66TaskLight", "TaskLightApp"):
        proc = subprocess.run(["/usr/bin/pgrep", "-x", process_name], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        values.extend(line.strip() for line in proc.stdout.splitlines() if line.strip())
    return values

running_pids = pids()
clients = load_clients()
latest = clients[0] if clients else {}
desktop_exists = desktop_app.exists()
desktop_target = str(desktop_app.resolve()) if desktop_exists else "missing"
status = "ok"
if len(running_pids) > 1:
    status = "multiple_apps"
elif running_pids and not latest:
    status = "stale_bundle"
elif not running_pids and not latest:
    status = "unknown"

print(f"running_app_pid={','.join(running_pids) if running_pids else 'none'}")
print(f"bundle_path={latest.get('bundle_path', 'unknown')}")
print(f"executable_path={latest.get('executable_path', 'unknown')}")
print(f"state_dir={latest.get('state_dir', 'unknown')}")
print(f"build_id={latest.get('build_id', 'unknown')}")
print(f"ui_client_updated_at={latest.get('updated_at', 'unknown')}")
print(f"desktop_app_path={desktop_app}")
print(f"desktop_alias_target={desktop_target}")
print(f"ui_client_count={len(clients)}")
print(f"STATUS={status}")
PY
)"

printf '%s\n' "$_client_output"
