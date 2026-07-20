#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
VERSION="$(tr -d '[:space:]' < VERSION)"
zsh ./build.sh

APP_PATH="/Applications/MagSafe Dark.app"
OLD_APP_PATH="/Applications/MagSafeDark.app"
BUILD_APP_PATH="build/MagSafe Dark.app"
DAEMON_BIN="/usr/local/libexec/magsafe-led-daemon"
CLIENT_BIN="/usr/local/libexec/magsafe-led-client"
SCHEDULER_BIN="/usr/local/libexec/magsafe-scheduler"
EDITOR_BIN="/usr/local/libexec/magsafe-schedule-editor"
CLI_IMPL="/usr/local/libexec/magsafe-dark-cli"
PLIST="/Library/LaunchDaemons/su.xyz.MagSafeDark.daemon.plist"
AGENT_LABEL="su.xyz.MagSafeDark.scheduler"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT_PLIST="$AGENT_DIR/${AGENT_LABEL}.plist"
USER_ID="$(id -u)"

sudo install -d -m 755 /usr/local/libexec /usr/local/bin /Library/LaunchDaemons
sudo install -o root -g wheel -m 755 .build/release/magsafe-led-daemon "$DAEMON_BIN"
sudo install -o root -g wheel -m 755 .build/release/magsafe-led-client "$CLIENT_BIN"
sudo install -o root -g wheel -m 755 .build/release/magsafe-scheduler "$SCHEDULER_BIN"
sudo install -o root -g wheel -m 755 .build/release/magsafe-schedule-editor "$EDITOR_BIN"
sudo install -o root -g wheel -m 755 scripts/magsafe-dark "$CLI_IMPL"
sudo install -o root -g wheel -m 755 scripts/codex-led /usr/local/bin/codex-led

cat > build/magsafe-dark <<'WRAPPER'
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
    if [[ "${1:-}" == "edit" ]]; then
      exec "$EDITOR"
    fi
    exec "$SCHEDULER" "${@:-status}"
    ;;
  system|off|green|orange|flash|blink-slow|blink-fast|blink-off)
    exec "$SCHEDULER" manual "$1"
    ;;
  *)
    exec "$CLI" "$@"
    ;;
esac
WRAPPER
chmod 755 build/magsafe-dark
sudo install -o root -g wheel -m 755 build/magsafe-dark /usr/local/bin/magsafe-dark

cat > build/su.xyz.MagSafeDark.daemon.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>su.xyz.MagSafeDark.daemon</string>
  <key>ProgramArguments</key><array><string>/usr/local/libexec/magsafe-led-daemon</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>/var/log/magsafe-dark-daemon.log</string>
  <key>StandardErrorPath</key><string>/var/log/magsafe-dark-daemon.log</string>
</dict>
</plist>
PLIST

sudo install -o root -g wheel -m 644 build/su.xyz.MagSafeDark.daemon.plist "$PLIST"
sudo launchctl bootout system/su.xyz.MagSafeDark.daemon 2>/dev/null || true
sudo rm -f /var/run/magsafe-dark.sock
sudo launchctl bootstrap system "$PLIST"
sudo launchctl enable system/su.xyz.MagSafeDark.daemon
sudo launchctl kickstart -k system/su.xyz.MagSafeDark.daemon

for _ in {1..50}; do
  [[ -S /var/run/magsafe-dark.sock ]] && "$CLIENT_BIN" ping >/dev/null 2>&1 && break
  sleep 0.1
done
"$CLIENT_BIN" ping >/dev/null || {
  print -u2 "MagSafe Dark daemon did not start. Check /var/log/magsafe-dark-daemon.log."
  exit 70
}

mkdir -p "$AGENT_DIR"
cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${AGENT_LABEL}</string>
  <key>ProgramArguments</key><array><string>${SCHEDULER_BIN}</string><string>run</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>${HOME}/Library/Logs/MagSafe Dark/scheduler.log</string>
  <key>StandardErrorPath</key><string>${HOME}/Library/Logs/MagSafe Dark/scheduler.log</string>
</dict>
</plist>
PLIST
chmod 644 "$AGENT_PLIST"
mkdir -p "$HOME/Library/Logs/MagSafe Dark"
"$SCHEDULER_BIN" init-default >/dev/null 2>&1 || true
launchctl bootout "gui/${USER_ID}/${AGENT_LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/${USER_ID}" "$AGENT_PLIST"
launchctl enable "gui/${USER_ID}/${AGENT_LABEL}"
launchctl kickstart -k "gui/${USER_ID}/${AGENT_LABEL}"

sudo rm -f /usr/local/libexec/magsafe-led-helper /etc/sudoers.d/magsafe-dark

if ! "$CLIENT_BIN" probe >/dev/null; then
  print -u2 "MagSafe ACLC is unavailable on this Mac. The application will be installed, but LED control is unsupported."
fi

pkill -x MagSafeDark 2>/dev/null || true
sleep 0.3
sudo rm -rf "$APP_PATH" "$OLD_APP_PATH"
sudo ditto "$BUILD_APP_PATH" "$APP_PATH"
sudo chown -R root:wheel "$APP_PATH"

open "$APP_PATH"
printf '\nInstalled MagSafe Dark %s with LaunchDaemon, schedule agent and visual editor.\n' "$VERSION"
