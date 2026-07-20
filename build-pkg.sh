#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
PROJECT_VERSION="$(tr -d '[:space:]' < VERSION)"
VERSION="${1:-$PROJECT_VERSION}"
APP_NAME="MagSafe Dark"
APP_PATH="build/${APP_NAME}.app"
PKG_ROOT="build/pkg-root"
PKG_SCRIPTS="build/pkg-scripts"
PKG_PATH="build/MagSafeDark-${VERSION}-unsigned.pkg"
[[ "$VERSION" == "$PROJECT_VERSION" ]] || { print -u2 "Requested package version $VERSION does not match VERSION file $PROJECT_VERSION"; exit 64; }

zsh ./build.sh
rm -rf "$PKG_ROOT" "$PKG_SCRIPTS" "$PKG_PATH" "$PKG_PATH.sha256"
mkdir -p "$PKG_ROOT/Applications" "$PKG_ROOT/usr/local/libexec" "$PKG_ROOT/usr/local/bin" "$PKG_ROOT/Library/LaunchDaemons" "$PKG_SCRIPTS"
ditto "$APP_PATH" "$PKG_ROOT/Applications/${APP_NAME}.app"
install -m 755 .build/release/magsafe-led-daemon "$PKG_ROOT/usr/local/libexec/magsafe-led-daemon"
install -m 755 .build/release/magsafe-led-client "$PKG_ROOT/usr/local/libexec/magsafe-led-client"
install -m 755 .build/release/magsafe-scheduler "$PKG_ROOT/usr/local/libexec/magsafe-scheduler"
install -m 755 .build/release/magsafe-schedule-editor "$PKG_ROOT/usr/local/libexec/magsafe-schedule-editor"
install -m 755 scripts/magsafe-dark "$PKG_ROOT/usr/local/libexec/magsafe-dark-cli"
install -m 755 scripts/codex-led "$PKG_ROOT/usr/local/bin/codex-led"

cat > "$PKG_ROOT/usr/local/bin/magsafe-dark" <<'WRAPPER'
#!/bin/zsh
set -euo pipefail
export MAGSAFE_DARK_HELPER="/usr/local/libexec/magsafe-led-client"
export MAGSAFE_DARK_SUDO="none"
SCHEDULER="/usr/local/libexec/magsafe-scheduler"
EDITOR="/usr/local/libexec/magsafe-schedule-editor"
CLI="/usr/local/libexec/magsafe-dark-cli"
case "${1:-}" in
  schedule)
    shift
    [[ "${1:-}" == edit ]] && exec "$EDITOR"
    exec "$SCHEDULER" "${@:-status}"
    ;;
  system|off|green|orange|flash|blink-slow|blink-fast|blink-off) exec "$SCHEDULER" manual "$1" ;;
  *) exec "$CLI" "$@" ;;
esac
WRAPPER
chmod 755 "$PKG_ROOT/usr/local/bin/magsafe-dark"

cat > "$PKG_ROOT/Library/LaunchDaemons/su.xyz.MagSafeDark.daemon.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>su.xyz.MagSafeDark.daemon</string>
<key>ProgramArguments</key><array><string>/usr/local/libexec/magsafe-led-daemon</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>ProcessType</key><string>Interactive</string>
<key>StandardOutPath</key><string>/var/log/magsafe-dark-daemon.log</string>
<key>StandardErrorPath</key><string>/var/log/magsafe-dark-daemon.log</string>
</dict></plist>
PLIST
chmod 644 "$PKG_ROOT/Library/LaunchDaemons/su.xyz.MagSafeDark.daemon.plist"

cat > "$PKG_SCRIPTS/postinstall" <<'POSTINSTALL'
#!/bin/zsh
set -euo pipefail
CONSOLE_USER=$(/usr/bin/stat -f '%Su' /dev/console)
DAEMON_LABEL="su.xyz.MagSafeDark.daemon"
PLIST="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
CLIENT="/usr/local/libexec/magsafe-led-client"
SCHEDULER="/usr/local/libexec/magsafe-scheduler"
EDITOR="/usr/local/libexec/magsafe-schedule-editor"
/usr/sbin/chown -R root:wheel "/Applications/MagSafe Dark.app"
/usr/sbin/chown root:wheel /usr/local/libexec/magsafe-led-daemon "$CLIENT" "$SCHEDULER" "$EDITOR" /usr/local/libexec/magsafe-dark-cli /usr/local/bin/magsafe-dark /usr/local/bin/codex-led "$PLIST"
/bin/chmod 755 /usr/local/libexec/magsafe-led-daemon "$CLIENT" "$SCHEDULER" "$EDITOR" /usr/local/libexec/magsafe-dark-cli /usr/local/bin/magsafe-dark /usr/local/bin/codex-led
/bin/chmod 644 "$PLIST"
/bin/rm -f /usr/local/libexec/magsafe-led-helper /etc/sudoers.d/magsafe-dark /var/run/magsafe-dark.sock
/bin/launchctl bootout system/$DAEMON_LABEL 2>/dev/null || true
/bin/launchctl bootstrap system "$PLIST"
/bin/launchctl enable system/$DAEMON_LABEL
/bin/launchctl kickstart -k system/$DAEMON_LABEL
for _ in {1..50}; do [[ -S /var/run/magsafe-dark.sock ]] && "$CLIENT" ping >/dev/null 2>&1 && break; /bin/sleep 0.1; done
"$CLIENT" ping >/dev/null 2>&1 || exit 70
if [[ -n "$CONSOLE_USER" && "$CONSOLE_USER" != root && "$CONSOLE_USER" != loginwindow ]]; then
  USER_ID=$(/usr/bin/id -u "$CONSOLE_USER")
  USER_HOME=$(/usr/bin/dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory | /usr/bin/awk '{print $2}')
  AGENT_LABEL="su.xyz.MagSafeDark.scheduler"
  AGENT_DIR="$USER_HOME/Library/LaunchAgents"
  AGENT_PLIST="$AGENT_DIR/${AGENT_LABEL}.plist"
  /bin/mkdir -p "$AGENT_DIR" "$USER_HOME/Library/Logs/MagSafe Dark"
  cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>${AGENT_LABEL}</string><key>ProgramArguments</key><array><string>${SCHEDULER}</string><string>run</string></array><key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ProcessType</key><string>Background</string><key>StandardOutPath</key><string>${USER_HOME}/Library/Logs/MagSafe Dark/scheduler.log</string><key>StandardErrorPath</key><string>${USER_HOME}/Library/Logs/MagSafe Dark/scheduler.log</string></dict></plist>
PLIST
  /usr/sbin/chown -R "$CONSOLE_USER":staff "$AGENT_DIR" "$USER_HOME/Library/Logs/MagSafe Dark"
  /bin/chmod 644 "$AGENT_PLIST"
  /bin/launchctl asuser "$USER_ID" /usr/bin/sudo -u "$CONSOLE_USER" "$SCHEDULER" init-default >/dev/null 2>&1 || true
  /bin/launchctl bootout "gui/${USER_ID}/${AGENT_LABEL}" 2>/dev/null || true
  /bin/launchctl bootstrap "gui/${USER_ID}" "$AGENT_PLIST"
  /bin/launchctl enable "gui/${USER_ID}/${AGENT_LABEL}"
  /bin/launchctl kickstart -k "gui/${USER_ID}/${AGENT_LABEL}"
  /bin/rm -rf "/Applications/MagSafeDark.app"
  /usr/bin/pkill -x MagSafeDark 2>/dev/null || true
  /bin/launchctl asuser "$USER_ID" /usr/bin/open "/Applications/MagSafe Dark.app" || true
fi
POSTINSTALL
chmod 755 "$PKG_SCRIPTS/postinstall"
pkgbuild --root "$PKG_ROOT" --scripts "$PKG_SCRIPTS" --identifier su.xyz.MagSafeDark --version "$VERSION" --install-location / "$PKG_PATH"
shasum -a 256 "$PKG_PATH" > "$PKG_PATH.sha256"
printf '\nBuilt package: %s/%s\n' "$PWD" "$PKG_PATH"
