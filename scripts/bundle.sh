#!/usr/bin/env bash
# 打包 dist/Herdr Perch.app（LSUIElement，ad-hoc 签名）
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="dist/Herdr Perch.app"

swift build -c "$CONFIG" --product PerchApp
BIN="$(swift build -c "$CONFIG" --show-bin-path)/PerchApp"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PerchApp"
# Icon from scripts/make-icon.py. Only the .icns for now: see that script for why the
# macOS 26 Assets.car (Resources/AppIcon.icon) is not shipped yet.
cp LICENSE NOTICE Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.herdr.perch</string>
    <key>CFBundleName</key><string>Herdr Perch</string>
    <key>CFBundleExecutable</key><string>PerchApp</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "$APP"
