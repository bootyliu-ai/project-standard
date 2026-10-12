#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
MODE="${1:-local}"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
OUTPUT_DIR="$ROOT_DIR/dist"
APP_DIR="$OUTPUT_DIR/ProjectStandard.app"
STAGE_DIR="$ROOT_DIR/.build/dmg-stage"

if [[ "$MODE" != "local" && "$MODE" != "notarized" ]]; then
  echo "用法：scripts/package-dmg.sh [local|notarized]" >&2
  exit 2
fi

if [[ "$MODE" == "notarized" ]]; then
  : "${PROJECT_STANDARD_SIGNING_IDENTITY:?请设置 PROJECT_STANDARD_SIGNING_IDENTITY}"
  : "${PROJECT_STANDARD_NOTARY_PROFILE:?请设置 PROJECT_STANDARD_NOTARY_PROFILE}"
fi

"$ROOT_DIR/scripts/package-release.sh" "$MODE"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
SUFFIX="local-unnotarized"
[[ "$MODE" == "notarized" ]] && SUFFIX="macos-universal"
DMG_NAME="ProjectStandard-$VERSION-$BUILD-$SUFFIX.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
ditto "$APP_DIR" "$STAGE_DIR/ProjectStandard.app"
ln -s /Applications "$STAGE_DIR/Applications"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"

hdiutil create \
  -volname "Project Standard" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$MODE" == "notarized" ]]; then
  xcrun notarytool submit \
    "$DMG_PATH" \
    --keychain-profile "$PROJECT_STANDARD_NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

(cd "$OUTPUT_DIR" && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")
rm -rf "$STAGE_DIR"
echo "$DMG_PATH"
echo "$DMG_PATH.sha256"
