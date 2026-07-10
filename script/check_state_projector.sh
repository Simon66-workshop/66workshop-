#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
LABEL="${TASKLIGHT_STATE_PROJECTOR_LABEL:-com.66tasklight.state-projector}"
UI_STATE_PATH="${TASKLIGHT_UI_STATE_PATH:-$STATE_DIR/ui_state.json}"
HEALTH_PATH="${TASKLIGHT_STATE_PROJECTOR_HEALTH_PATH:-$STATE_DIR/state_projector_health.json}"
MAX_AGE="${TASKLIGHT_STATE_PROJECTOR_MAX_AGE_SECONDS:-5}"
EXPECTED_HASH="${TASKLIGHT_STATE_PROJECTOR_EXPECTED_HASH:-sha256:$(shasum -a 256 "$ROOT_DIR/script/state_projector.py" | awk '{print $1}')}"

process_list="$(pgrep -f "$ROOT_DIR/script/state_projector.py --watch" || true)"
[ -n "$process_list" ] || process_list="$(pgrep -f "state_projector.py --watch" || true)"
process_count="${TASKLIGHT_STATE_PROJECTOR_PROCESS_COUNT_OVERRIDE:-}"
if [ -z "$process_count" ]; then
  process_count="$(printf '%s\n' "$process_list" | awk 'NF{count++} END{print count+0}')"
fi
process_pid="$(printf '%s\n' "$process_list" | awk 'NF{print; exit}')"
[ -n "$process_pid" ] || process_pid="$(launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | awk '/^[[:space:]]pid = /{print $3; exit}' || true)"
[ -n "$process_pid" ] || process_pid="none"

launchctl_status="not_running"
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  launchctl_status="running"
fi

_projector_output="$(python3 - "$UI_STATE_PATH" "$HEALTH_PATH" "$MAX_AGE" "$EXPECTED_HASH" "$process_count" <<'PY'
import json
import sys
import time
from datetime import datetime
from pathlib import Path

ui_state_path = Path(sys.argv[1]).expanduser()
health_path = Path(sys.argv[2]).expanduser()
max_age = float(sys.argv[3])
expected_hash = sys.argv[4]
process_count = int(sys.argv[5])

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
runtime_candidates = ui_state.get("runtime_candidates") if isinstance(ui_state.get("runtime_candidates"), list) else []
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

projector_version = ui_state.get("projector_version", "none")
projector_hash = ui_state.get("projector_code_hash", "none")
source = ui_state.get("source", "none")
writer_status = diagnostics.get("writer_status", "ok")
if source != "state_projector" or projector_version not in {"M3.7", "M3.8"} or projector_hash != expected_hash:
    writer_status = "old_writer"
if process_count > 1:
    writer_status = "multiple_writers"
if not fresh:
    writer_status = "stale" if writer_status == "ok" else writer_status

top_candidates = diagnostics.get("top_runtime_candidates")
if not isinstance(top_candidates, list):
    top_candidates = runtime_candidates[:5]
top_candidates_text = json.dumps(top_candidates, ensure_ascii=True, sort_keys=True, separators=(',', ':'))
pretty_candidates = []
for candidate in top_candidates[:5]:
    if not isinstance(candidate, dict):
        continue
    pretty_candidates.append(
        "{id} scope={scope} score={score} fresh={fresh} identity={identity} consistency={consistency} cause={cause} age={age} why_active={why_active} why_ignored={why_ignored}".format(
            id=candidate.get("candidate_id", "none"),
            scope=candidate.get("display_scope", "none"),
            score=candidate.get("runtime_score", "none"),
            fresh=candidate.get("freshness_score", "none"),
            identity=candidate.get("identity_score", "none"),
            consistency=candidate.get("consistency_score", "none"),
            cause=candidate.get("state_cause", "none"),
            age=candidate.get("age_sec", "none"),
            why_active=candidate.get("why_active", "none"),
            why_ignored=candidate.get("why_ignored", "none"),
        )
    )
top_candidates_pretty = " | ".join(pretty_candidates) if pretty_candidates else "none"

print(f"ui_state_path={ui_state_path}")
print(f"ui_state_status={ui_status}")
print(f"projector_version={projector_version}")
print(f"projector_pid={ui_state.get('projector_pid', 'none')}")
print(f"projector_code_hash={projector_hash}")
print(f"expected_code_hash={expected_hash}")
print(f"projector_launch_label={ui_state.get('projector_launch_label', 'none')}")
print(f"projector_instance_id={ui_state.get('projector_instance_id', 'none')}")
print(f"writer_status={writer_status}")
print(f"ui_state_global_status={ui_state.get('global_status', 'none')}")
print(f"global_status={ui_state.get('global_status', 'none')}")
print(f"display_title={ui_state.get('global_display_title', 'none')}")
print(f"counts={json.dumps(counts, ensure_ascii=True, sort_keys=True, separators=(',', ':'))}")
print(f"signal_bus_status={diagnostics.get('signal_bus_status', 'none')}")
print(f"signal_bus_record_count={diagnostics.get('signal_bus_record_count', 'none')}")
print(f"signal_bus_source_counts={json.dumps(diagnostics.get('signal_bus_source_counts', {}), ensure_ascii=True, sort_keys=True, separators=(',', ':'))}")
print(f"latest_hook_signal_age_sec={diagnostics.get('latest_hook_signal_age_sec', 'none')}")
print(f"latest_hook_bridge_signal_age_sec={diagnostics.get('latest_hook_bridge_signal_age_sec', 'none')}")
print(f"latest_process_observer_signal_age_sec={diagnostics.get('latest_process_observer_signal_age_sec', 'none')}")
print(f"latest_private_probe_signal_age_sec={diagnostics.get('latest_private_probe_signal_age_sec', 'none')}")
print(f"latest_private_probe_status={diagnostics.get('latest_private_probe_status', 'none')}")
print(f"latest_private_probe_quality={diagnostics.get('latest_private_probe_quality', 'none')}")
print(f"appserver_thread_signal_status={diagnostics.get('appserver_thread_signal_status', 'none')}")
print(f"appserver_live_thread_count={diagnostics.get('appserver_live_thread_count', 'none')}")
print(f"appserver_active_count={diagnostics.get('appserver_active_count', counts.get('appserver_active', 'none'))}")
print(f"process_observed_count={diagnostics.get('process_observed_count', counts.get('process_observed', 'none'))}")
print(f"weak_observed_count={diagnostics.get('weak_observed_count', 'none')}")
print(f"latest_appserver_thread_age_sec={diagnostics.get('latest_appserver_thread_age_sec', 'none')}")
print(f"latest_appserver_state_cause={diagnostics.get('latest_appserver_state_cause', 'none')}")
print(f"appserver_thread_watcher_status={diagnostics.get('appserver_thread_watcher_status', 'none')}")
print(f"runtime_candidate_count={diagnostics.get('runtime_candidate_count', len(runtime_candidates))}")
print(f"top_runtime_candidates={top_candidates_text}")
print(f"top_runtime_candidates_pretty={top_candidates_pretty}")
print(f"pending_verify_count={counts.get('pending_verify_count', 0)}")
print(f"latest_pending_turn_id={latest_pending_turn_id}")
print(f"projector_reason={reason_text}")
print(f"fallback_reason={diagnostics.get('fallback_reason', 'none')}")
print(f"latest_turn_binding_canonical_identity={diagnostics.get('latest_turn_binding_canonical_identity', 'none')}")
print(f"latest_turn_binding_aliases={json.dumps(diagnostics.get('latest_turn_binding_aliases', []), ensure_ascii=True, sort_keys=True, separators=(',', ':'))}")
print(f"binding_identity_count={diagnostics.get('binding_identity_count', 'none')}")
print(f"latest_bridge_decision={diagnostics.get('latest_bridge_decision', 'none')}")
print(f"current_thread_signal_source={diagnostics.get('current_thread_signal_source', 'none')}")
print(f"current_thread_signal_status={diagnostics.get('current_thread_signal_status', 'none')}")
quota = ui_state.get("quota") if isinstance(ui_state.get("quota"), dict) else {}
print(f"quota_status={diagnostics.get('quota_status', quota.get('status', 'none'))}")
print(f"quota_fresh={diagnostics.get('quota_fresh', quota.get('fresh', 'none'))}")
print(f"quota_source={diagnostics.get('quota_source', quota.get('source', 'none'))}")
print(f"quota_effective_remaining_percent={quota.get('effective_remaining_percent', 'none')}")
print(f"quota_probe_status={diagnostics.get('quota_probe_status', 'none')}")
print(f"quota_probe_mode={diagnostics.get('quota_probe_mode', quota.get('probe_mode', 'none'))}")
print(f"quota_bucket_id={quota.get('bucket_id', 'none')}")
print(f"quota_raw_window_count={diagnostics.get('quota_raw_window_count', quota.get('raw_window_count', 'none'))}")
print(f"quota_captured_at={quota.get('captured_at', 'none')}")
print(f"quota_captured_age_sec={quota.get('captured_age_sec', 'none')}")
print(f"quota_state_path={diagnostics.get('quota_state_path', 'none')}")
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
writer_status="$(printf '%s\n' "$_projector_output" | awk -F= '/^writer_status=/{print $2}' | tail -1)"

status="ok"
if [ "$ui_state_status" = "unreadable" ] || [ "$health_status" = "unreadable" ] || [ "$health_state" = "error" ]; then
  status="error"
elif [ "$ui_state_status" = "missing" ] && [ "$process_pid" = "none" ]; then
  status="not_running"
elif [ "$writer_status" = "old_writer" ] || [ "$writer_status" = "multiple_writers" ]; then
  status="error"
elif [ "$fresh" != "yes" ]; then
  status="stale"
fi

echo "launchctl_status=$launchctl_status"
echo "process_pid=$process_pid"
echo "process_count=$process_count"
printf '%s\n' "$_projector_output"
echo "coverage_hint=run ./script/check_codex_thread_coverage.sh when Codex UI and LuckyCat disagree"
echo "STATUS=$status"
