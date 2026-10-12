#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CONFIGURATION="${1:-release}"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$BUILD_DIR/ProjectStandard.app"

source "$ROOT_DIR/scripts/swift-env.zsh"
cd "$ROOT_DIR"
swift build --disable-sandbox --scratch-path "$PROJECT_STANDARD_SCRATCH_PATH" -c "$CONFIGURATION"
BIN_DIR="$(swift build --disable-sandbox --scratch-path "$PROJECT_STANDARD_SCRATCH_PATH" -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/ProjectStandard" "$APP_DIR/Contents/MacOS/ProjectStandard"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - --entitlements "$ROOT_DIR/Resources/ProjectStandard.entitlements" "$APP_DIR"
fi

echo "$APP_DIR"
