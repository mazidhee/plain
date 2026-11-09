#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Plain"
BIN_NAME="Plain"
BUNDLE_ID="com.mazidhee.plain"
VERSION="${VERSION:-1.0.0}"
APP_BUNDLE="build/${APP_NAME}.app"

echo "==> Building (universal: arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "==> Icon (drawn by the app itself)"
mkdir -p build
"${BIN_DIR}/${BIN_NAME}" --make-icon build/icon-1024.png
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o build/AppIcon.icns

echo "==> Assembling ${APP_BUNDLE}"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "${BIN_DIR}/${BIN_NAME}" "$APP_BUNDLE/Contents/MacOS/${BIN_NAME}"
cp build/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Plain</string>
    <key>CFBundleDisplayName</key><string>Plain</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${BIN_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>${BUNDLE_ID}</string>
            <key>CFBundleURLSchemes</key><array><string>plain</string></array>
        </dict>
    </array>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key><true/>
    </dict>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 mazidhee. MIT licensed.</string>
</dict>
</plist>
PLIST

echo "==> Signing (ad hoc, designated requirement pinned to the bundle id)"
# The default ad-hoc requirement is the build's cdhash, so macOS would forget
# notification and login-item approvals after every rebuild.
codesign --force --deep --sign - -r="designated => identifier \"${BUNDLE_ID}\"" "$APP_BUNDLE"

echo
echo "Built: $APP_BUNDLE"
echo "Install: ./scripts/install.sh"
