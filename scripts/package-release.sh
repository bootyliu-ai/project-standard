#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
MODE="${1:-local}"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Resources/ProjectStandard.entitlements"
WORK_DIR="$ROOT_DIR/.build/distribution"
OUTPUT_DIR="$ROOT_DIR/dist"
APP_DIR="$OUTPUT_DIR/ProjectStandard.app"

if [[ "$MODE" != "local" && "$MODE" != "notarized" ]]; then
  echo "用法：scripts/package-release.sh [local|notarized]" >&2
  exit 2
fi

if [[ "$MODE" == "notarized" ]]; then
  : "${PROJECT_STANDARD_SIGNING_IDENTITY:?请设置 PROJECT_STANDARD_SIGNING_IDENTITY 为 Developer ID Application 证书名称}"
  : "${PROJECT_STANDARD_NOTARY_PROFILE:?请设置 PROJECT_STANDARD_NOTARY_PROFILE 为 notarytool Keychain profile 名称}"
fi

source "$ROOT_DIR/scripts/swift-env.zsh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
ZIP_SUFFIX="local-unnotarized"

rm -rf "$WORK_DIR" "$APP_DIR"
mkdir -p "$WORK_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$OUTPUT_DIR"

typeset -a binaries
for arch in arm64 x86_64; do
  triple="${arch}-apple-macosx13.0"
  scratch="$WORK_DIR/build-$arch"
  swift build \
    --disable-sandbox \
    --scratch-path "$scratch" \
    --configuration release \
    --triple "$triple" \
    --product ProjectStandard
  bin_dir="$(swift build \
    --disable-sandbox \
    --scratch-path "$scratch" \
    --configuration release \
    --triple "$triple" \
    --show-bin-path)"
  binaries+=("$bin_dir/ProjectStandard")
done

xcrun lipo -create "${binaries[@]}" -output "$APP_DIR/Contents/MacOS/ProjectStandard"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"

if [[ "$MODE" == "notarized" ]]; then
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$PROJECT_STANDARD_SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_DIR"
  ZIP_SUFFIX="macos-universal"
else
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
ARCHS="$(xcrun lipo -archs "$APP_DIR/Contents/MacOS/ProjectStandard")"
if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
  echo "Universal 架构校验失败：$ARCHS" >&2
  exit 1
fi

ZIP_PATH="$OUTPUT_DIR/ProjectStandard-$VERSION-$BUILD-$ZIP_SUFFIX.zip"
rm -f "$ZIP_PATH" "$ZIP_PATH.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

if [[ "$MODE" == "notarized" ]]; then
  xcrun notarytool submit \
    "$ZIP_PATH" \
    --keychain-profile "$PROJECT_STANDARD_NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$APP_DIR"
  xcrun stapler validate "$APP_DIR"
  rm -f "$ZIP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
  spctl --assess --type execute --verbose=4 "$APP_DIR"
fi

(cd "$OUTPUT_DIR" && shasum -a 256 "${ZIP_PATH:t}" > "${ZIP_PATH:t}.sha256")
echo "$ZIP_PATH"
echo "$ZIP_PATH.sha256"
