#!/bin/bash
# TimeZoneBar build script: compile -> assemble the .app -> sign
set -euo pipefail
cd "$(dirname "$0")"

NAME="TimeZoneBar"
DIST="dist"
APP="$DIST/$NAME.app"

echo "==> 1/4 swift build (release)"
swift build -c release --disable-sandbox

echo "==> 2/4 Assembling the .app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$NAME" "$APP/Contents/MacOS/$NAME"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> 3/4 Ad-hoc signing"
codesign --force --sign - "$APP"

echo "==> 4/4 Verifying"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP" && echo "Signature verified"

echo "Done: $APP"
