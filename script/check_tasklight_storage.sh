#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-storage-check-XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

python3 "$ROOT_DIR/script/tasklight_storage_audit.py" \
  --state-dir "${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}" \
  --project-root "$ROOT_DIR" \
  --output-json "$TMP_DIR/storage.json" \
  --output-md "$TMP_DIR/storage.md" >/dev/null

python3 "$ROOT_DIR/script/tasklight_storage_maintenance.py" \
  --state-dir "${TASKLIGHT_STATE_DIR:-$HOME/.66tasklight}" \
  --report-only \
  --output-json "$TMP_DIR/maintenance.json" >/dev/null

printf 'task_files=%s\n' "$(jq '.directories.tasks.file_count' "$TMP_DIR/storage.json")"
printf 'event_bytes=%s\n' "$(jq '.files.events.file_bytes' "$TMP_DIR/storage.json")"
printf 'maintenance_mode=%s\n' "$(jq -r '.mode' "$TMP_DIR/maintenance.json")"
printf 'maintenance_planned=%s\n' "$(jq '.planned_count' "$TMP_DIR/maintenance.json")"
echo 'STATUS=ok'
