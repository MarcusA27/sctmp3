#!/bin/bash
# Builds sctmp3.app — a self-contained macOS app bundle.
set -e
cd "$(dirname "$0")"

APP="sctmp3.app"
BIN_NAME="sctmp3app"

echo "→ compiling (release)…"
swift build -c release

echo "→ (re)generating icon…"
rm -rf AppIcon.iconset && mkdir -p AppIcon.iconset
swift makeicon.swift AppIcon.iconset >/dev/null
iconutil -c icns AppIcon.iconset -o AppIcon.icns

echo "→ assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>sctmp3</string>
    <key>CFBundleDisplayName</key><string>sctmp3</string>
    <key>CFBundleIdentifier</key><string>com.marcusarocha.sctmp3</string>
    <key>CFBundleVersion</key><string>$(date +%s)</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>$BIN_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc codesign so Gatekeeper lets a locally-built app run.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "✓ built $(pwd)/$APP"
