#!/bin/bash
# Builds dist/Explorer-<version>.dmg (drag Explorer.app onto Applications) + SHA-256.
# Uses only built-in macOS tools (hdiutil). Run ./build_app.sh first (release.sh does this for you).
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(tr -d '[:space:]' < VERSION)
APP=build/Explorer.app
[ -d "$APP" ] || ./build_app.sh
mkdir -p dist
DMG="dist/Explorer-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/Explorer.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me.txt" <<TXT
Explorer $VERSION

1. Drag Explorer.app onto the Applications folder.
2. The first time you open it: right-click Explorer.app -> Open
   (the app is not notarized by Apple).
3. Optional: in Explorer choose  Explorer menu -> Install 'explorermac' Command...
   to open folders from Terminal:  explorermac /Users

Source and docs: https://github.com/preslav-panayotov/explorer-macos
TXT

rm -f "$DMG"
hdiutil create -volname "Explorer $VERSION" -srcfolder "$STAGE" -ov -format UDZO -fs APFS "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
( cd dist && shasum -a 256 "Explorer-$VERSION.dmg" > "Explorer-$VERSION.dmg.sha256" )
echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
cat "dist/Explorer-$VERSION.dmg.sha256"
