#!/bin/bash
# Builds a release Explorer.app into ./build
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(tr -d '[:space:]' < VERSION)
swift build -c release
APP=build/Explorer.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Explorer "$APP/Contents/MacOS/Explorer"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Explorer</string>
<key>CFBundleDisplayName</key><string>Explorer</string>
<key>CFBundleIdentifier</key><string>com.local.explorer</string>
<key>CFBundleExecutable</key><string>Explorer</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PL
codesign --force --sign - "$APP"
echo "Built $APP"
