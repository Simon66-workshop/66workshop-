#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="$ROOT_DIR/script/codex_private_state_probe.py"
FUSION="$ROOT_DIR/script/codex_signal_fusion.py"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-private-probe-XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

make_db() {
  local codex_home="$1"
  local thread_id="$2"
  local mode="$3"
  mkdir -p "$codex_home"
  python3 - "$codex_home" "$thread_id" "$mode" <<'PY'
import sqlite3
import sys
import time
from pathlib import Path

home = Path(sys.argv[1])
thread_id = sys.argv[2]
mode = sys.argv[3]
con = sqlite3.connect(home / "logs_2.sqlite")
con.execute("create table logs (id integer primary key autoincrement, ts integer not null, ts_nanos integer not null, level text not null, target text not null, feedback_log_body text, module_path text, file text, line integer, thread_id text, process_uuid text, estimated_bytes integer not null default 0)")
if mode == "global":
    con.execute("insert into logs (ts, ts_nanos, level, target, thread_id) values (?, 0, 'INFO', 'smoke', ?)", (int(time.time()), "other-thread"))
elif mode == "thread":
    con.execute("insert into logs (ts, ts_nanos, level, target, thread_id) values (?, 0, 'INFO', 'smoke', ?)", (int(time.time()), thread_id))
con.commit()
con.close()
PY
}

thread_id="thread-private"
global_home="$TMP_DIR/global"
make_db "$global_home" "$thread_id" global
global_probe="$("$PROBE" --codex-home "$global_home" --thread-id "$thread_id")"
global_fusion="$(printf '%s\n' "$global_probe" | "$FUSION" --input -)"

python3 - "$global_probe" "$global_fusion" <<'PY'
import json
import sys

probe = json.loads(sys.argv[1])
fusion = json.loads(sys.argv[2])
assert probe["thread_scoped"] is False, probe
assert probe["confidence"] < 0.70, probe
assert probe["decision"] in {"observed_only", "unknown_short_lease"}, probe
assert fusion["decision"] != "refresh_managed_heartbeat", fusion
PY

thread_home="$TMP_DIR/thread"
make_db "$thread_home" "$thread_id" thread
thread_probe="$("$PROBE" --codex-home "$thread_home" --thread-id "$thread_id")"
thread_fusion="$(printf '%s\n' "$thread_probe" | "$FUSION" --input -)"

python3 - "$thread_probe" "$thread_fusion" <<'PY'
import json
import sys

probe = json.loads(sys.argv[1])
fusion = json.loads(sys.argv[2])
assert probe["thread_scoped"] is True, probe
assert probe["confidence"] >= 0.70, probe
assert fusion["decision"] == "refresh_managed_heartbeat", fusion
PY

unknown_probe="$("$PROBE" --codex-home "$TMP_DIR/missing" --thread-id "$thread_id")"
unknown_fusion="$(printf '%s\n' "$unknown_probe" | "$FUSION" --input -)"
python3 - "$unknown_probe" "$unknown_fusion" <<'PY'
import json
import sys

probe = json.loads(sys.argv[1])
fusion = json.loads(sys.argv[2])
assert probe["inferred_status"] == "unknown", probe
assert fusion["decision"] == "short_lease", fusion
PY

echo "smoke_private_probe_confidence: ok"
