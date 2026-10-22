#!/usr/bin/env bash
# 把 dist/Herdr Perch.app 打成 dist/Herdr-Perch-<版本>.dmg（App + 指向 /Applications 的链接，拖入即安装）
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Herdr Perch.app"
[[ -d "$APP" ]] || { echo "Package the app with scripts/bundle.sh first" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="dist/Herdr-Perch-$VERSION.dmg"

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/perch-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "Herdr Perch" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "$DMG"
