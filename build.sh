#!/bin/bash
# TimeZoneBar 一键构建脚本：编译 -> 组装 .app -> 签名
set -euo pipefail
cd "$(dirname "$0")"

NAME="TimeZoneBar"
DIST="dist"
APP="$DIST/$NAME.app"

echo "==> 1/4 swift build (release)"
swift build -c release

echo "==> 2/4 组装 .app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$NAME" "$APP/Contents/MacOS/$NAME"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> 3/4 ad-hoc 签名"
codesign --force --sign - "$APP"

echo "==> 4/4 校验"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP" && echo "签名校验 OK"

echo "完成：$APP"
