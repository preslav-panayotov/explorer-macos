#!/bin/bash
# Packages the current VERSION into dist/Explorer-<version>-macOS.zip (+ SHA-256).
# Usage: ./release.sh        then tag + publish (see CONTRIBUTING.md / README "Releases")
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(tr -d '[:space:]' < VERSION)
swift test 2>&1 | grep -E "Executed .* tests" | head -1
./build_app.sh
mkdir -p dist
ZIP="dist/Explorer-$VERSION-macOS.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Explorer.app "$ZIP"
( cd dist && shasum -a 256 "Explorer-$VERSION-macOS.zip" > "Explorer-$VERSION-macOS.zip.sha256" )
echo "Created $ZIP"
cat "dist/Explorer-$VERSION-macOS.zip.sha256"
