#!/bin/bash
# TravelTime build script: compile -> assemble the .app -> sign
set -euo pipefail
cd "$(dirname "$0")"

NAME="TravelTime"
DIST="dist"
APP="$DIST/$NAME.app"

# --- Clean dist: keep only the current .app -------------------------------
# macOS Launchpad renders every .app in dist/ — and every zip's Info.plist —
# as its own icon ("ghost icon" issue). Before each build we remove all zips
# and any .app that is not the current one, so dist always holds exactly one
# TravelTime.app.
echo "==> 0/4 Cleaning dist (old artifacts)"
mkdir -p "$DIST"
rm -rf "$DIST"/*.zip
for d in "$DIST"/*.app; do
    if [ -d "$d" ] && [ "$(basename "$d")" != "$NAME.app" ]; then
        rm -rf "$d"
        echo "  removed stale: $(basename "$d")"
    fi
done

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
# Bundle any other top-level assets from Resources/ (avatar image, etc.)
# so the .app stays self-contained. Skip subdirectories and known special files.
if [ -d "Resources" ]; then
    for f in Resources/*; do
        [ -d "$f" ] && continue
        case "$(basename "$f")" in
            Info.plist|AppIcon.icns|.DS_Store) continue ;;
        esac
        cp "$f" "$APP/Contents/Resources/$(basename "$f")"
    done
fi

echo "==> 3/4 Code signing (self-signed certificate: 'TimeZoneBar Developer')"
codesign --force --sign "TimeZoneBar Developer" --options runtime --identifier com.atom.tzbar "$APP"

echo "==> 4/4 Verifying"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP" && echo "Signature verified"

echo "==> 5/4 Deploying to /Applications (single source of truth)"
pkill -9 -f "$NAME" 2>/dev/null || true
sleep 1
rm -rf "/Applications/$NAME.app"
ditto "$APP" "/Applications/$NAME.app"
echo "  deployed: /Applications/$NAME.app"

echo "==> 6/4 Cleaning dist so Launchpad never sees a duplicate"
rm -rf "$APP"
echo "  removed: $APP (build artifact deployed already)"

echo "Done: /Applications/$NAME.app"

# --- Optional release packaging -------------------------------------------
# `./build.sh release` additionally zips the deployed app into release/ and
# prints its SHA256. The updater refuses to install a release whose notes lack
# a "SHA256: <64-hex>" line, so paste the printed hash into the GitHub release
# notes or users will not be able to update.
if [ "${1:-}" = "release" ]; then
    echo "==> 7/4 Packaging release zip + SHA256"
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "/Applications/$NAME.app/Contents/Info.plist" 2>/dev/null || echo "0.0.0")
    ZIP="release/$NAME-$VERSION.app.zip"
    mkdir -p release
    rm -f "$ZIP"
    ditto -c -k --sequesterRsrc --keepParent "/Applications/$NAME.app" "$ZIP"
    HASH=$(shasum -a 256 "$ZIP" | awk '{print $1}')
    echo "  zip: $ZIP"
    echo "  SHA256: $HASH"
    echo "  --> Paste into the GitHub release notes as: SHA256: $HASH"
fi
