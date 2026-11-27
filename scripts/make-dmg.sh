#!/bin/bash
# Builds a Release copy of PromptVault and packages it as a compressed DMG in build/release/,
# with a SHA-256 checksum next to it.
#
# Usage (from anywhere in the repository): scripts/make-dmg.sh
#
# Signing: the app keeps the project's ad-hoc signature, so a downloaded copy has to be approved once
# in System Settings > Privacy & Security before it opens. Removing that step needs a Developer ID
# certificate and notarization, which this script doesn't do yet.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME=PromptVault
DERIVED=build/ReleaseBuild
OUT=build/release

echo "==> Building $APP_NAME (Release)"
rm -rf "$DERIVED"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -derivedDataPath "$DERIVED" -destination "generic/platform=macOS" ONLY_ACTIVE_ARCH=NO -quiet clean build
APP="$DERIVED/Build/Products/Release/$APP_NAME.app"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
ARCHS=$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")
echo "==> Version $VERSION ($BUILD), architectures: $ARCHS"

echo "==> Verifying the code signature"
codesign --verify --deep --strict "$APP"

echo "==> Creating the disk image"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
mkdir -p "$OUT"
DMG="$OUT/$APP_NAME-$VERSION.dmg"
rm -f "$DMG" "$DMG.sha256"
hdiutil create -quiet -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG"
hdiutil verify -quiet "$DMG"

(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" | tee "$(basename "$DMG").sha256")
echo "==> Done: $DMG"
