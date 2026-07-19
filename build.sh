#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
rm -rf build/MagSafeDark.app
mkdir -p build/MagSafeDark.app/Contents/MacOS build/MagSafeDark.app/Contents/Resources
cp .build/release/MagSafeDark build/MagSafeDark.app/Contents/MacOS/
cat > build/MagSafeDark.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>su.xyz.MagSafeDark</string>
<key>CFBundleName</key><string>MagSafe Dark</string>
<key>CFBundleExecutable</key><string>MagSafeDark</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
codesign --force --deep --sign - build/MagSafeDark.app
printf '\nBuilt: %s/build/MagSafeDark.app\n' "$PWD"
