#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
APP_BUNDLE="build/Plain.app"
STAGE="build/dmg-stage"
DMG="build/Plain-${VERSION}.dmg"

VERSION="$VERSION" ./build.sh

echo "==> Verifying signature"
codesign --verify --deep --strict "$APP_BUNDLE"
lipo -archs "$APP_BUNDLE/Contents/MacOS/Plain"

echo "==> Staging DMG"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP_BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me.txt" <<'TXT'
Plain

Drag Plain onto the Applications folder, then open it. It lives in the menu bar.

First launch on another Mac:
Plain is not notarized. Right-click Plain in Applications, choose Open, then Open.
If macOS says the app is damaged, run this once in Terminal:

    xattr -dr com.apple.quarantine /Applications/Plain.app
TXT

echo "==> Creating ${DMG}"
hdiutil create -volname "Plain" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
shasum -a 256 "$DMG" | tee "${DMG}.sha256"
cp "$DMG" "build/Plain.dmg"
echo
echo "DMG: $DMG"
du -h "$DMG"
