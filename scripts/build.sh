#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product BartenderCraft
APP_DESTINATION="${BARTENDERCRAFT_APP_OUTPUT:-$PWD/build/BartenderCraft.app}"
source scripts/stage-app.sh
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/BartenderCraft "$APP/Contents/MacOS/BartenderCraft"
swift scripts/generate-icon.swift "$APP/Contents/Resources/BartenderCraft.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>BartenderCraft</string>
<key>CFBundleDisplayName</key><string>BartenderCraft</string>
<key>CFBundleExecutable</key><string>BartenderCraft</string>
<key>CFBundleIconFile</key><string>BartenderCraft</string>
<key>CFBundleIdentifier</key><string>com.dgclaw.BarGarden</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSScreenCaptureUsageDescription</key><string>BartenderCraft uses menu bar captures to display optional icon thumbnails.</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - --identifier com.dgclaw.BarGarden "$APP"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --verify --strict "$APP"
publish_app
