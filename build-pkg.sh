#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${1:-1.2.1}"
APP_NAME="MagSafe Dark"
APP_PATH="build/${APP_NAME}.app"
PKG_ROOT="build/pkg-root"
PKG_SCRIPTS="build/pkg-scripts"
PKG_PATH="build/MagSafeDark-${VERSION}-unsigned.pkg"

zsh ./build.sh

rm -rf "$PKG_ROOT" "$PKG_SCRIPTS" "$PKG_PATH"
mkdir -p \
  "$PKG_ROOT/Applications" \
  "$PKG_ROOT/usr/local/libexec" \
  "$PKG_ROOT/usr/local/bin" \
  "$PKG_SCRIPTS"

ditto "$APP_PATH" "$PKG_ROOT/Applications/${APP_NAME}.app"
install -m 755 .build/release/magsafe-led-helper "$PKG_ROOT/usr/local/libexec/magsafe-led-helper"
install -m 755 scripts/magsafe-dark "$PKG_ROOT/usr/local/bin/magsafe-dark"
install -m 755 scripts/codex-led "$PKG_ROOT/usr/local/bin/codex-led"

cat > "$PKG_SCRIPTS/postinstall" <<'POSTINSTALL'
#!/bin/zsh
set -euo pipefail

CONSOLE_USER=$(/usr/bin/stat -f '%Su' /dev/console)
if [[ -z "$CONSOLE_USER" || "$CONSOLE_USER" == "root" || "$CONSOLE_USER" == "loginwindow" ]]; then
  print -u2 "Could not determine the logged-in user."
  exit 1
fi

HELPER="/usr/local/libexec/magsafe-led-helper"
/bin/mkdir -p /etc/sudoers.d
cat > /etc/sudoers.d/magsafe-dark <<EOF
${CONSOLE_USER} ALL=(root) NOPASSWD: ${HELPER} off, ${HELPER} system, ${HELPER} green, ${HELPER} orange, ${HELPER} flash, ${HELPER} blink-slow, ${HELPER} blink-fast, ${HELPER} blink-off, ${HELPER} status
EOF

/usr/sbin/chown root:wheel /etc/sudoers.d/magsafe-dark
/bin/chmod 440 /etc/sudoers.d/magsafe-dark
if ! /usr/sbin/visudo -cf /etc/sudoers.d/magsafe-dark; then
  /bin/rm -f /etc/sudoers.d/magsafe-dark
  exit 1
fi

/usr/sbin/chown -R root:wheel "/Applications/MagSafe Dark.app"
/usr/sbin/chown root:wheel "$HELPER" /usr/local/bin/magsafe-dark /usr/local/bin/codex-led
/bin/chmod 755 "$HELPER" /usr/local/bin/magsafe-dark /usr/local/bin/codex-led
/bin/rm -rf "/Applications/MagSafeDark.app"
/usr/bin/pkill -x MagSafeDark 2>/dev/null || true

USER_ID=$(/usr/bin/id -u "$CONSOLE_USER")
/bin/launchctl asuser "$USER_ID" /usr/bin/open "/Applications/MagSafe Dark.app" || true
exit 0
POSTINSTALL

chmod 755 "$PKG_SCRIPTS/postinstall"
pkgbuild \
  --root "$PKG_ROOT" \
  --scripts "$PKG_SCRIPTS" \
  --identifier su.xyz.MagSafeDark \
  --version "$VERSION" \
  --install-location / \
  "$PKG_PATH"

printf '\nBuilt package: %s/%s\n' "$PWD" "$PKG_PATH"
printf 'Test with: sudo installer -pkg "%s" -target /\n' "$PKG_PATH"
