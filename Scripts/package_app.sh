#!/usr/bin/env bash
# Builds TokensVSRainForest.app (window + menu bar item, ad-hoc signed) in the repo root.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product TokensVSRainForest
APP="TokensVSRainForest.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TokensVSRainForest "$APP/Contents/MacOS/TokensVSRainForest"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp web/index.html "$APP/Contents/Resources/simulation.html"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>TokensVSRainForest</string>
  <key>CFBundleDisplayName</key><string>Tokens vs. Regenwald</string>
  <key>CFBundleIdentifier</key><string>com.tokensvsrainforest.app</string>
  <key>CFBundleExecutable</key><string>TokensVSRainForest</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP — start with: open $APP"
