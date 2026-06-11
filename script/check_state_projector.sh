#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
LABEL="${TASKLIGHT_STATE_PROJECTOR_LABEL:-com.66tasklight.state-projector}"
UI_STATE_PATH="${TASKLIGHT_UI_STATE_PATH:-$STATE_DIR/ui_state.json}"
HEALTH_PATH="${TASKLIGHT_STATE_PROJECTOR_HEALTH_PATH:-$STATE_DIR/state_projector_health.json}"
MAX_AGE="${TASKLIGHT_STATE_PROJECTOR_MAX_AGE_SECONDS:-5}"

process_pid="$(pgrep -f "$ROOT_DIR/script/state_projector.py --watch" | head -1 || true)"
[ -n "$process_pid" ] || process_pid="$(pgrep -f "state_projector.py --watch" | head -1 || true)"
[ -n "$process_pid" ] || process_pid="none"

launchctl_status="not_running"
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  launchctl_status="running"
fi

_projector_output="$(python3 - "$UI_STATE_PATH" "$HEALTH_PATH" "$MAX_AGE" <<'PY'
import json
import sys
import time
from datetime import datetime
from pathlib import Path

ui_state_path = Path(sys.argv[1]).expanduser()
health_path = Path(sys.argv[2]).expanduser()
max_age = float(sys.argv[3])

def parse_ts(value):
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        pass
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None

def load(path):
    try:
        return json.loads(path.read_text(encoding="utf-8")), "readable"
    except FileNotFoundError:
        return {}, "missing"
    except Exception:
        return {}, "unreadable"

ui_state, ui_status = load(ui_state_path)
health, health_status = load(health_path)
updated = ui_state.get("projector_generated_at") or health.get("updated_at") or health.get("last_run_at")
ts = parse_ts(updated)
age = None if ts is None else max(0, int(time.time() - ts))
fresh = age is not None and age <= max_age
counts = ui_state.get("counts") if isinstance(ui_state.get("counts"), dict) else {}
diagnostics = ui_state.get("diagnostics") if isinstance(ui_state.get("diagnostics"), dict) else {}
tasks = ui_state.get("tasks") if isinstance(ui_state.get("tasks"), list) else []
latest_pending_turn_id = "none"
for task in tasks:
    if isinstance(task, dict) and task.get("display_scope") == "pending_verify":
        latest_pending_turn_id = str(task.get("turn_id") or task.get("task_id") or "none")
        break
reason = diagnostics.get("projector_reason")
if isinstance(reason, list):
    reason_text = ",".join(str(item) for item in reason)
elif reason is None:
    reason_text = "none"
else:
    reason_text = str(reason)

print(f"ui_state_path={ui_state_path}")
print(f"ui_state_status={ui_status}")
print(f"ui_state_global_status={ui_state.get('global_status', 'none')}")
print(f"global_status={ui_state.get('global_status', 'none')}")
print(f"display_title={ui_state.get('global_display_title', 'none')}")
print(f"counts={json.dumps(counts, ensure_ascii=True, sort_keys=True, separators=(',', ':'))}")
print(f"pending_verify_count={counts.get('pending_verify_count', 0)}")
print(f"latest_pending_turn_id={latest_pending_turn_id}")
print(f"projector_reason={reason_text}")
print(f"fallback_reason={diagnostics.get('fallback_reason', 'none')}")
print(f"ui_state_generated_at={ui_state.get('projector_generated_at', 'none')}")
print(f"state_projector_health_path={health_path}")
print(f"state_projector_health_status={health_status}")
print(f"state_projector_health_state={health.get('status', 'none') if health_status == 'readable' else 'none'}")
print(f"state_projector_age_sec={'none' if age is None else age}")
print(f"ui_state_age_sec={'none' if age is None else age}")
print(f"state_projector_fresh={'yes' if fresh else 'no'}")
PY
)"

ui_state_status="$(printf '%s\n' "$_projector_output" | awk -F= '/^ui_state_status=/{print $2}' | tail -1)"
health_status="$(printf '%s\n' "$_projector_output" | awk -F= '/^state_projector_health_status=/{print $2}' | tail -1)"
health_state="$(printf '%s\n' "$_projector_output" | awk -F= '/^state_projector_health_state=/{print $2}' | tail -1)"
fresh="$(printf '%s\n' "$_projector_output" | awk -F= '/^state_projector_fresh=/{print $2}' | tail -1)"

status="ok"
if [ "$ui_state_status" = "unreadable" ] || [ "$health_status" = "unreadable" ] || [ "$health_state" = "error" ]; then
  status="error"
elif [ "$ui_state_status" = "missing" ] && [ "$process_pid" = "none" ]; then
  status="not_running"
elif [ "$fresh" != "yes" ]; then
  status="stale"
fi

echo "launchctl_status=$launchctl_status"
echo "process_pid=$process_pid"
printf '%s\n' "$_projector_output"
echo "STATUS=$status"
