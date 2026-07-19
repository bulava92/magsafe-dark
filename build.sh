#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MagSafeDark"
APP_DIR="build/${APP_NAME}.app"
ICON_SOURCE="Resources/AppIcon.png"
ICONSET_DIR="build/AppIcon.iconset"
ICON_FILE="build/AppIcon.icns"

if [[ ! -f "$ICON_SOURCE" ]]; then
  print -u2 "Missing app icon: $ICON_SOURCE"
  exit 1
fi

ICON_WIDTH=$(sips -g pixelWidth "$ICON_SOURCE" | awk '/pixelWidth/ { print $2 }')
ICON_HEIGHT=$(sips -g pixelHeight "$ICON_SOURCE" | awk '/pixelHeight/ { print $2 }')

if [[ -z "$ICON_WIDTH" || -z "$ICON_HEIGHT" || "$ICON_WIDTH" != "$ICON_HEIGHT" ]]; then
  print -u2 "AppIcon.png must be a square PNG. Current size: ${ICON_WIDTH:-unknown}x${ICON_HEIGHT:-unknown}"
  exit 1
fi

if (( ICON_WIDTH < 1024 )); then
  print -u2 "AppIcon.png must be at least 1024x1024. Current size: ${ICON_WIDTH}x${ICON_HEIGHT}"
  exit 1
fi

swift build -c release

rm -rf "$APP_DIR" "$ICONSET_DIR" "$ICON_FILE"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$ICONSET_DIR"
cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/"

make_icon() {
  local size="$1"
  local output="$2"
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/$output" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
cp "$ICON_FILE" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>su.xyz.MagSafeDark</string>
<key>CFBundleName</key><string>MagSafe Dark</string>
<key>CFBundleDisplayName</key><string>MagSafe Dark</string>
<key>CFBundleExecutable</key><string>MagSafeDark</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"
printf '\nBuilt: %s/%s\n' "$PWD" "$APP_DIR"
