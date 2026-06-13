#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}"
COVERAGE_DIR="${TASKLIGHT_WORKSPACE_COVERAGE_DIR:-$STATE_DIR/workspace_coverage}"
DISCOVERED="$COVERAGE_DIR/workspaces.json"
LATEST="$COVERAGE_DIR/latest.json"

usage() {
  cat >&2 <<'EOF'
usage:
  install_hooks_for_workspaces.sh --preferred
  install_hooks_for_workspaces.sh --all-discovered
  install_hooks_for_workspaces.sh --from-report [--include-non-preferred]
  install_hooks_for_workspaces.sh --workspace /path/to/project [--workspace /path/to/other]
EOF
}

mode=""
include_non_preferred="no"
workspaces=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --preferred)
      mode="preferred"
      shift
      ;;
    --all-discovered)
      mode="all_discovered"
      shift
      ;;
    --from-report)
      mode="from_report"
      shift
      ;;
    --include-non-preferred)
      include_non_preferred="yes"
      shift
      ;;
    --workspace)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      workspaces+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ ${#workspaces[@]} -eq 0 ]]; then
  case "$mode" in
    preferred)
      "$ROOT_DIR/script/check_codex_workspaces_coverage.sh" >/dev/null
      workspace_list="$(mktemp)"
      python3 - "$LATEST" >"$workspace_list" <<'PY'
import json, sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for item in payload.get("workspaces", []):
    if item.get("preferred") and item.get("coverage_status") in {"missing_hooks", "invalid_hooks"}:
        print(item["workspace"])
PY
      while IFS= read -r line; do
        [[ -n "$line" ]] && workspaces+=("$line")
      done <"$workspace_list"
      rm -f "$workspace_list"
      ;;
    all_discovered)
      echo "warning=--all-discovered will install hooks into every discovered candidate workspace" >&2
      python3 "$ROOT_DIR/script/discover_codex_workspaces.py" >/dev/null
      workspace_list="$(mktemp)"
      python3 - "$DISCOVERED" >"$workspace_list" <<'PY'
import json, sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for item in payload.get("workspaces", []):
    print(item["workspace"])
PY
      while IFS= read -r line; do
        [[ -n "$line" ]] && workspaces+=("$line")
      done <"$workspace_list"
      rm -f "$workspace_list"
      ;;
    from_report)
      [[ -f "$LATEST" ]] || "$ROOT_DIR/script/check_codex_workspaces_coverage.sh" >/dev/null
      workspace_list="$(mktemp)"
      python3 - "$LATEST" "$include_non_preferred" >"$workspace_list" <<'PY'
import json, sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
include_non_preferred = sys.argv[2] == "yes"
for item in payload.get("workspaces", []):
    if item.get("coverage_status") in {"missing_hooks", "invalid_hooks"}:
        if item.get("preferred") or include_non_preferred:
            print(item["workspace"])
PY
      while IFS= read -r line; do
        [[ -n "$line" ]] && workspaces+=("$line")
      done <"$workspace_list"
      rm -f "$workspace_list"
      ;;
    *)
      usage
      exit 2
      ;;
  esac
fi

if [[ ${#workspaces[@]} -eq 0 ]]; then
  echo "workspace_hooks_batch=no_targets"
  exit 0
fi

installed=0
for workspace in "${workspaces[@]}"; do
  if [[ ! -d "$workspace" ]]; then
    echo "workspace_hooks=skipped workspace=$workspace reason=missing_directory"
    continue
  fi
  "$ROOT_DIR/script/install_hooks_for_workspace.sh" "$workspace"
  installed=$((installed + 1))
done

echo "workspace_hooks_batch=installed"
echo "installed_count=$installed"
echo "next_action=open each Codex workspace and trust project hooks in the Codex UI"
