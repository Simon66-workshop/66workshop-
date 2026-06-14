#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
QUOTA_PATH="${TASKLIGHT_QUOTA_STATE_PATH:-$STATE_DIR/quota_state.json}"
UI_STATE_PATH="${TASKLIGHT_UI_STATE_PATH:-$STATE_DIR/ui_state.json}"

python3 - "$QUOTA_PATH" "$UI_STATE_PATH" <<'PY'
import json
import sys
from pathlib import Path

quota_path = Path(sys.argv[1]).expanduser()
ui_state_path = Path(sys.argv[2]).expanduser()

def load(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None

quota = load(quota_path)
ui = load(ui_state_path)
ui_quota = ui.get("quota") if isinstance(ui, dict) and isinstance(ui.get("quota"), dict) else None

if not isinstance(quota, dict):
    print(f"quota_state_path={quota_path}")
    print("exists=no")
    print("STATUS=missing")
    raise SystemExit(0)

display_windows = quota.get("display_windows") if isinstance(quota.get("display_windows"), list) else []
legacy_windows = quota.get("windows") if isinstance(quota.get("windows"), list) else []

def priority(window):
    bucket = str(window.get("bucket_id") or "").lower()
    remaining = int(window.get("remaining_percent") or 0)
    if bucket == "codex":
        return (0, 0)
    if "codex" in bucket and not bucket.startswith("codex_"):
        return (1, remaining)
    if bucket.startswith("codex_"):
        return (2, remaining)
    return (3, remaining)

def select_display(windows):
    grouped = {}
    for window in windows:
        if not isinstance(window, dict) or not isinstance(window.get("remaining_percent"), int):
            continue
        key = window.get("window_duration_mins") if window.get("window_duration_mins") is not None else window.get("label")
        grouped.setdefault(key, []).append(window)
    selected = [sorted(candidates, key=priority)[0] for candidates in grouped.values()]
    return sorted(selected, key=lambda item: item.get("window_duration_mins") if item.get("window_duration_mins") is not None else 10**9)

windows = display_windows or select_display(legacy_windows)
raw_windows = quota.get("raw_windows") if isinstance(quota.get("raw_windows"), list) else legacy_windows
short = windows[0] if windows else {}
long = windows[-1] if len(windows) > 1 else {}
reset = quota.get("manual_resets") if isinstance(quota.get("manual_resets"), dict) else {}
parts = []
if isinstance(short.get("remaining_percent"), int):
    parts.append(str(short["remaining_percent"]))
if isinstance(long.get("remaining_percent"), int) and long is not short:
    parts.append(str(long["remaining_percent"]))
if reset.get("available_count") is not None:
    parts.append(f"R{reset.get('available_count')}")
compact = "⚡" + ("·".join(parts) if parts else "Q?")

print(f"quota_state_path={quota_path}")
print("exists=yes")
print(f"source={quota.get('source')}")
print(f"captured_at={quota.get('captured_at')}")
print(f"fresh={quota.get('fresh')}")
print(f"quota_status={quota.get('quota_status')}")
print(f"effective_remaining_percent={quota.get('effective_remaining_percent')}")
print(f"raw_window_count={len(raw_windows)}")
print(f"display_window_count={len(windows)}")
print(f"short_window={short.get('label')} {short.get('remaining_percent')} bucket_id={short.get('bucket_id')} reset={short.get('reset_label')}")
print(f"long_window={long.get('label')} {long.get('remaining_percent')} bucket_id={long.get('bucket_id')} reset={long.get('reset_label')}")
print(f"manual_resets={reset.get('available_count')}")
print(f"recommendation={quota.get('recommendation')}")
print(f"warnings={','.join(str(item) for item in (quota.get('warnings') or [])) or 'none'}")
print(f"ui_state_quota_exists={'yes' if ui_quota else 'no'}")
if ui_quota:
    print(f"ui_state_quota_probe_mode={ui_quota.get('probe_mode')}")
    print(f"ui_state_quota_bucket_id={ui_quota.get('bucket_id')}")
    print(f"ui_state_quota_raw_window_count={ui_quota.get('raw_window_count')}")
print(f"compact_text=\"{compact}\"")
print("STATUS=ok")
PY
