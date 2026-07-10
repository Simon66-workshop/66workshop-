#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-hook-bridge-cache-XXXXXX")"
trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

python3 - "$ROOT_DIR" "$STATE_DIR" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
state = Path(sys.argv[2])
bindings = state / "turn_bindings"
bindings.mkdir(parents=True)
for index in range(320):
    (bindings / f"released-{index}.json").write_text(json.dumps({"status": "released"}), encoding="utf-8")
active = bindings / "active.json"
active.write_text(json.dumps({"status": "active"}), encoding="utf-8")

sys.path.insert(0, str(root / "script"))
import hook_signal_bridge as bridge

offsets = bridge.offsets_default()
first = bridge.active_binding_paths(bindings, offsets, reconcile_seconds=60)
assert first == [active], first
assert bridge.count_active_bindings(offsets) == 1, offsets

# The next idle cycle reads only the cached active path; released history stays
# out of the hot path until the scheduled reconciliation window.
second = bridge.active_binding_paths(bindings, offsets, reconcile_seconds=60)
assert second == [active], second
assert len(offsets["active_binding_paths"]) == 1, offsets
PY

rg -q 'active_paths = active_binding_paths' "$ROOT_DIR/script/hook_signal_bridge.py"
rg -q 'new_active_binding' "$ROOT_DIR/script/hook_signal_bridge.py"
rg -q 'binding_reconcile_seconds' "$ROOT_DIR/script/hook_signal_bridge.py"

echo "smoke_hook_bridge_idle_cache: ok"
