#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Building MacDuoBlur..."
rm -rf build
mkdir -p build/MacDuoBlur.app/Contents/MacOS
mkdir -p build/MacDuoBlur.app/Contents/Resources

# Compile optimized binary
swiftc -O Sources/MacDuoBlur/main.swift -o build/MacDuoBlur.app/Contents/MacOS/MacDuoBlur

# Write Info.plist
cat << 'EOF' > build/MacDuoBlur.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MacDuoBlur</string>
    <key>CFBundleIdentifier</key>
    <string>com.shayanmaher.MacDuoBlur</string>
    <key>CFBundleName</key>
    <string>MacDuoBlur</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc sign app
codesign --force --deep --sign - build/MacDuoBlur.app

echo "==> Packaging DMG..."
DMG_STAGING="build/dmg_staging"
mkdir -p "$DMG_STAGING"
cp -R build/MacDuoBlur.app "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f build/MacDuoBlur.dmg
hdiutil create -volname "MacDuoBlur" -srcfolder "$DMG_STAGING" -ov -format UDZO build/MacDuoBlur.dmg

echo "==> Done! Output: build/MacDuoBlur.dmg"
