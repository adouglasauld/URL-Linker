#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
APP="/private/tmp/URLLinker-artifacts/URL Linker.app"
mkdir -p "$PWD/dist"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/URLLinker" "$APP/Contents/MacOS/URLLinker"
cp App/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/Junction-LICENSE.txt"
for bundle in "$BIN"/*.bundle; do [ ! -e "$bundle" ] || cp -R "$bundle" "$APP/Contents/Resources/"; done
cp App/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"
codesign --force --options runtime --sign "${CODESIGN_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
ditto --norsrc --noextattr -c -k --keepParent "$APP" "$PWD/dist/URL-Linker.zip"
printf '%s\n' "$APP" "$PWD/dist/URL-Linker.zip"
