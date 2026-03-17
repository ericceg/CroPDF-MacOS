#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
DMG_NAME="${2:-CroPDF}"

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "usage: $0 [debug|release] [dmg-name]" >&2
  exit 1
fi

cd "$ROOT_DIR"

"$ROOT_DIR/scripts/build_app.sh" "$CONFIGURATION"

STAGING_DIR="$(mktemp -d "$ROOT_DIR/dist/dmg-staging.XXXXXX")"
DMG_PATH="$ROOT_DIR/dist/${DMG_NAME}.dmg"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cp -R "$ROOT_DIR/dist/CroPDF.app" "$STAGING_DIR/CroPDF.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "CroPDF" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Built $DMG_PATH"
