#!/usr/bin/env bash
# Sync built i18n resources to Go shared package
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/resource/i18n/build-for-go"
DEST="$ROOT/go/packages/shared/i18n/resources"

echo "==> Syncing i18n resources to Go package..."

if [ ! -d "$SRC" ]; then
  echo "ERROR: Build directory not found. Run 'bash resource/i18n/build.sh' first."
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"

cp -r "$SRC"/* "$DEST/"

echo "==> Synced $(find "$DEST" -name '*.json' | wc -l) translation files"
echo "==> Done!"
