#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "usage: $0 [debug|release]" >&2
  exit 1
fi

cd "$ROOT_DIR"

swift build --disable-sandbox -c "$CONFIGURATION"

BIN_DIR="$(swift build --disable-sandbox -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$ROOT_DIR/dist/CroPDF.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_DIR/CroPDFMacOS" "$MACOS_DIR/CroPDFMacOS"
cp -R "$BIN_DIR/CroPDFMacOS_CroPDFMacOS.bundle" "$RESOURCES_DIR/CroPDFMacOS_CroPDFMacOS.bundle"
cp "$ROOT_DIR/src/Resources/CroPDF.icns" "$RESOURCES_DIR/CroPDF.icns"
cp "$ROOT_DIR/scripts/Info.plist" "$CONTENTS_DIR/Info.plist"

echo "Built $APP_DIR"
