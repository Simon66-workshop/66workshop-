#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
STATE_DIR="$TMP_ROOT/state"
SCAN_ROOT="$TMP_ROOT/workspaces"
CONFIG_PATH="$TMP_ROOT/workspace_coverage.json"
mkdir -p "$STATE_DIR" "$SCAN_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_WORKSPACE_COVERAGE_DIR="$STATE_DIR/workspace_coverage"
export TASKLIGHT_WORKSPACE_COVERAGE_CONFIG="$CONFIG_PATH"

mkdir -p \
  "$SCAN_ROOT/preferred-missing" \
  "$SCAN_ROOT/preferred-existing/.codex" \
  "$SCAN_ROOT/non-preferred-missing" \
  "$SCAN_ROOT/non-preferred-invalid/.codex" \
  "$SCAN_ROOT/backup/ignored-project"
touch \
  "$SCAN_ROOT/preferred-missing/AGENTS.md" \
  "$SCAN_ROOT/preferred-existing/AGENTS.md" \
  "$SCAN_ROOT/non-preferred-missing/AGENTS.md" \
  "$SCAN_ROOT/non-preferred-invalid/AGENTS.md" \
  "$SCAN_ROOT/backup/ignored-project/AGENTS.md"
printf '{broken\n' > "$SCAN_ROOT/non-preferred-invalid/.codex/hooks.json"
"$ROOT_DIR/script/install_hooks_for_workspace.sh" "$SCAN_ROOT/preferred-existing" >/dev/null

python3 - "$CONFIG_PATH" "$SCAN_ROOT" <<'PY'
import json, sys
from pathlib import Path
config = Path(sys.argv[1])
root = Path(sys.argv[2])
payload = {
    "include_roots": [str(root)],
    "exclude_patterns": ["**/backup/**"],
    "preferred_workspaces": [
        str(root / "preferred-missing"),
        str(root / "preferred-existing"),
    ],
}
config.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
PY

python3 "$ROOT_DIR/script/discover_codex_workspaces.py" --json >/dev/null
"$ROOT_DIR/script/check_codex_workspaces_coverage.sh" --skip-appserver >/dev/null

python3 - "$STATE_DIR/workspace_coverage/latest.json" "$STATE_DIR/workspace_coverage/latest.md" "$STATE_DIR/workspace_coverage/run_status.json" <<'PY'
import json, sys
from pathlib import Path
latest = Path(sys.argv[1])
report = Path(sys.argv[2])
status = Path(sys.argv[3])
payload = json.loads(latest.read_text(encoding="utf-8"))
by_name = {item["name"]: item for item in payload["workspaces"]}
assert by_name["preferred-missing"]["coverage_status"] == "missing_hooks", by_name
assert by_name["preferred-missing"]["workspace_group"] == "preferred", by_name
assert by_name["preferred-existing"]["workspace_group"] == "preferred", by_name
assert by_name["non-preferred-missing"]["coverage_status"] == "missing_hooks", by_name
assert by_name["non-preferred-missing"]["workspace_group"] == "discovered_non_preferred", by_name
assert by_name["non-preferred-invalid"]["coverage_status"] == "invalid_hooks", by_name
assert "ignored-project" not in by_name, by_name
summary = payload["summary"]
assert summary["preferred_workspace_count"] == 2, summary
assert summary["preferred_missing_hooks"] == 1, summary
assert report.exists(), report
run_status = json.loads(status.read_text(encoding="utf-8"))
assert run_status["message"] == "常用项目 1 个缺 hooks", run_status
PY

"$ROOT_DIR/script/install_hooks_for_workspaces.sh" --preferred >/dev/null
python3 - "$SCAN_ROOT/preferred-missing/.codex/hooks.json" "$SCAN_ROOT/non-preferred-missing/.codex/hooks.json" <<'PY'
import json, sys
from pathlib import Path
preferred = Path(sys.argv[1])
non_preferred = Path(sys.argv[2])
assert "hooks" in json.loads(preferred.read_text(encoding="utf-8"))
assert not non_preferred.exists(), non_preferred
PY

"$ROOT_DIR/script/check_codex_workspaces_coverage.sh" --skip-appserver >/dev/null
"$ROOT_DIR/script/install_hooks_for_workspaces.sh" --from-report >/dev/null
python3 - "$SCAN_ROOT/non-preferred-invalid/.codex/hooks.json" "$SCAN_ROOT/non-preferred-missing/.codex/hooks.json" <<'PY'
from pathlib import Path
invalid = Path(__import__("sys").argv[1])
missing = Path(__import__("sys").argv[2])
assert invalid.read_text(encoding="utf-8").startswith("{broken"), invalid
assert not missing.exists(), missing
PY

"$ROOT_DIR/script/install_hooks_for_workspaces.sh" --from-report --include-non-preferred >/dev/null
python3 - "$SCAN_ROOT/non-preferred-invalid/.codex/hooks.json" "$SCAN_ROOT/non-preferred-missing/.codex/hooks.json" <<'PY'
import json, sys
from pathlib import Path
for raw in sys.argv[1:]:
    payload = json.loads(Path(raw).read_text(encoding="utf-8"))
    assert "hooks" in payload
PY

echo "smoke_workspace_coverage=ok"
