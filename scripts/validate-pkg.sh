#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
PKG_PATH="${1:-build/MagSafeDark-${VERSION_VALUE}-unsigned.pkg}"

[[ -f "$PKG_PATH" ]] || {
  print -u2 "Package not found: $PKG_PATH"
  print -u2 "Build it with: zsh ./build-pkg.sh"
  exit 66
}

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/magsafe-pkg-validation.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
pkgutil --check-signature "$PKG_PATH" > "$TEMP_DIR/signature.txt" 2>&1 || true
pkgutil --expand-full "$PKG_PATH" "$TEMP_DIR/expanded"

PACKAGE_INFO="$TEMP_DIR/expanded/PackageInfo"
[[ -f "$PACKAGE_INFO" ]] || { print -u2 "PackageInfo is missing"; exit 1; }
grep -q 'identifier="su.xyz.MagSafeDark"' "$PACKAGE_INFO"
grep -q "version=\"$VERSION_VALUE\"" "$PACKAGE_INFO"

PAYLOAD_ROOT="$TEMP_DIR/expanded/Payload"
[[ -d "$PAYLOAD_ROOT/Applications/MagSafe Dark.app" ]]
[[ -x "$PAYLOAD_ROOT/usr/local/libexec/magsafe-led-daemon" ]]
[[ -x "$PAYLOAD_ROOT/usr/local/libexec/magsafe-led-client" ]]
[[ ! -e "$PAYLOAD_ROOT/usr/local/libexec/magsafe-led-helper" ]]
[[ -x "$PAYLOAD_ROOT/usr/local/libexec/magsafe-dark-cli" ]]
[[ -x "$PAYLOAD_ROOT/usr/local/bin/magsafe-dark" ]]
[[ -x "$PAYLOAD_ROOT/usr/local/bin/codex-led" ]]
[[ -f "$PAYLOAD_ROOT/Library/LaunchDaemons/su.xyz.MagSafeDark.daemon.plist" ]]

grep -q 'MAGSAFE_DARK_SUDO="none"' "$PAYLOAD_ROOT/usr/local/bin/magsafe-dark"
grep -q '/usr/local/libexec/magsafe-dark-cli' "$PAYLOAD_ROOT/usr/local/bin/magsafe-dark"

PLIST="$PAYLOAD_ROOT/Library/LaunchDaemons/su.xyz.MagSafeDark.daemon.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$PLIST")" == "su.xyz.MagSafeDark.daemon" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$PLIST")" == "/usr/local/libexec/magsafe-led-daemon" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :RunAtLoad' "$PLIST")" == true ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :KeepAlive' "$PLIST")" == true ]]

POSTINSTALL="$TEMP_DIR/expanded/Scripts/postinstall"
[[ -x "$POSTINSTALL" ]]
grep -q 'launchctl bootstrap system' "$POSTINSTALL"
grep -q 'magsafe-led-client.*ping' "$POSTINSTALL"
grep -q 'rm -f .*magsafe-led-helper.*sudoers.d/magsafe-dark' "$POSTINSTALL"
! grep -q 'NOPASSWD' "$POSTINSTALL"
! grep -q 'visudo' "$POSTINSTALL"

APP_EXECUTABLE="$PAYLOAD_ROOT/Applications/MagSafe Dark.app/Contents/MacOS/MagSafeDark"
[[ -x "$APP_EXECUTABLE" ]]
! strings "$APP_EXECUTABLE" | grep -q '/usr/bin/sudo'
! strings "$APP_EXECUTABLE" | grep -q 'magsafe-led-helper'
strings "$APP_EXECUTABLE" | grep -q 'magsafe-led-client'

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PAYLOAD_ROOT/Applications/MagSafe Dark.app/Contents/Info.plist")"
[[ "$APP_VERSION" == "$VERSION_VALUE" ]] || {
  print -u2 "Application version $APP_VERSION does not match VERSION $VERSION_VALUE"
  exit 1
}

shasum -a 256 "$PKG_PATH" > "$PKG_PATH.sha256"
print "Package validation passed: $PKG_PATH"
print "Checksum written: $PKG_PATH.sha256"
cat "$TEMP_DIR/signature.txt"
