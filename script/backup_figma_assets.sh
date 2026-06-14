#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="$ROOT_DIR/backups/figma"
mkdir -p "$BACKUP_DIR"

TS="$(date +%Y%m%d_%H%M%S)"
ARCHIVE="$BACKUP_DIR/66tasklight-figma-backup-$TS.tar.gz"

REQUIRED_FILES=(
  "$ROOT_DIR/docs/assets/66tasklight-cover.png"
  "$ROOT_DIR/docs/assets/66tasklight-thumbnail.png"
  "$ROOT_DIR/docs/assets/66tasklight-thumbnail-1024.png"
  "$ROOT_DIR/mac/66TaskLight/AppAssets/AppIcon.icns"
  "$ROOT_DIR/mac/66TaskLight/AppAssets/AppIcon1024.png"
)

EXISTING=(
  $(printf '%s\n' "${REQUIRED_FILES[@]}" | while read -r f; do [ -e "$f" ] && printf '%s\n' "$f"; done)
)

if [ ${#EXISTING[@]} -eq 0 ]; then
  echo "No target figma/artifact files found." >&2
  exit 1
fi

tar -czf "$ARCHIVE" -C "$ROOT_DIR" \
  ${EXISTING[@]#$ROOT_DIR/}

echo "Created: $ARCHIVE"
