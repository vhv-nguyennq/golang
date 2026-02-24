#!/usr/bin/env bash
# Helper script to add a new translation key
# Usage: ./scripts/add-i18n-key.sh <namespace> <key> <vi_text> <en_text>

set -euo pipefail

if [ $# -lt 4 ]; then
  echo "Usage: $0 <namespace> <key> <vi_text> <en_text>"
  echo "Example: $0 common user_deleted 'Người dùng đã bị xóa' 'User has been deleted'"
  exit 1
fi

NAMESPACE="$1"
KEY="$2"
VI_TEXT="$3"
EN_TEXT="$4"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
NS_DIR="$ROOT/resource/i18n/source/$NAMESPACE"

if [ ! -d "$NS_DIR" ]; then
  echo "Creating new namespace: $NAMESPACE"
  mkdir -p "$NS_DIR"
  echo '{}' > "$NS_DIR/vi.json"
  echo '{}' > "$NS_DIR/en.json"
fi

# Add to Vietnamese
jq --arg key "$KEY" --arg value "$VI_TEXT" '. + {($key): $value}' \
  "$NS_DIR/vi.json" > "$NS_DIR/vi.json.tmp" && mv "$NS_DIR/vi.json.tmp" "$NS_DIR/vi.json"

# Add to English
jq --arg key "$KEY" --arg value "$EN_TEXT" '. + {($key): $value}' \
  "$NS_DIR/en.json" > "$NS_DIR/en.json.tmp" && mv "$NS_DIR/en.json.tmp" "$NS_DIR/en.json"

echo "✅ Added key '$KEY' to namespace '$NAMESPACE'"
echo "   vi: $VI_TEXT"
echo "   en: $EN_TEXT"
echo ""
echo "Next steps:"
echo "  1. Run: bash resource/i18n/build.sh"
echo "  2. Use in Go: bundle.T(\"$KEY\")"
echo "  3. Use in React: t('$NAMESPACE:$KEY')"
