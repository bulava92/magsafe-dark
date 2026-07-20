#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
APP_IDENTITY="${MAGSAFE_DARK_APP_SIGN_IDENTITY:?Set MAGSAFE_DARK_APP_SIGN_IDENTITY to a Developer ID Application identity}"
PKG_IDENTITY="${MAGSAFE_DARK_PKG_SIGN_IDENTITY:?Set MAGSAFE_DARK_PKG_SIGN_IDENTITY to a Developer ID Installer identity}"
NOTARY_PROFILE="${MAGSAFE_DARK_NOTARY_PROFILE:?Set MAGSAFE_DARK_NOTARY_PROFILE to a notarytool keychain profile}"
BUILD_NUMBER="${MAGSAFE_DARK_BUILD_NUMBER:-1}"
UNSIGNED_PKG="build/MagSafeDark-${VERSION_VALUE}-unsigned.pkg"
SIGNED_PKG="build/MagSafeDark-${VERSION_VALUE}.pkg"

MAGSAFE_DARK_APP_SIGN_IDENTITY="$APP_IDENTITY" MAGSAFE_DARK_BUILD_NUMBER="$BUILD_NUMBER" zsh ./build-pkg.sh "$VERSION_VALUE"

productsign --sign "$PKG_IDENTITY" "$UNSIGNED_PKG" "$SIGNED_PKG"
pkgutil --check-signature "$SIGNED_PKG"
xcrun notarytool submit "$SIGNED_PKG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$SIGNED_PKG"
xcrun stapler validate "$SIGNED_PKG"
spctl --assess --type install --verbose=4 "$SIGNED_PKG"
shasum -a 256 "$SIGNED_PKG" > "$SIGNED_PKG.sha256"

print "Signed and notarized package: $SIGNED_PKG"
print "Checksum: $SIGNED_PKG.sha256"
