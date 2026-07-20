#!/bin/zsh
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/MagSafe Dark"
LOG_DIR="$HOME/Library/Logs/MagSafe Dark"
CLIENT="/usr/local/libexec/magsafe-led-client"
CLI="/usr/local/bin/magsafe-dark"
DAEMON_LABEL="su.xyz.MagSafeDark.daemon"
SCHEDULER_LABEL="su.xyz.MagSafeDark.scheduler"
PLIST="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
AGENT_PLIST="$HOME/Library/LaunchAgents/${SCHEDULER_LABEL}.plist"
USER_ID="$(id -u)"

if [[ -x "$CLI" ]]; then
  "$CLI" schedule disable >/dev/null 2>&1 || true
  /usr/local/libexec/magsafe-led-client system >/dev/null 2>&1 || true
elif [[ -x "$CLIENT" ]]; then
  "$CLIENT" system >/dev/null 2>&1 || true
fi

pkill -x MagSafeDark 2>/dev/null || true
pkill -x magsafe-schedule-editor 2>/dev/null || true
launchctl bootout "gui/${USER_ID}/${SCHEDULER_LABEL}" 2>/dev/null || true
rm -f "$AGENT_PLIST"
sudo launchctl bootout system/$DAEMON_LABEL 2>/dev/null || true
sudo rm -f /var/run/magsafe-dark.sock

sudo rm -rf "/Applications/MagSafe Dark.app" /Applications/MagSafeDark.app
sudo rm -f \
  /usr/local/libexec/magsafe-led-daemon \
  /usr/local/libexec/magsafe-led-client \
  /usr/local/libexec/magsafe-led-helper \
  /usr/local/libexec/magsafe-scheduler \
  /usr/local/libexec/magsafe-schedule-editor \
  /usr/local/libexec/magsafe-dark-cli \
  "$CLI" \
  /usr/local/bin/codex-led \
  "$PLIST" \
  /etc/sudoers.d/magsafe-dark \
  /var/log/magsafe-dark-daemon.log

sudo pkgutil --forget su.xyz.MagSafeDark >/dev/null 2>&1 || true
rm -rf "$APP_SUPPORT" "$LOG_DIR" "$HOME/Library/Caches/su.xyz.MagSafeDark" "$HOME/Library/Saved Application State/su.xyz.MagSafeDark.savedState"
defaults delete su.xyz.MagSafeDark >/dev/null 2>&1 || true
printf 'Removed MagSafe Dark, daemon, scheduler, editor, settings, schedule, state and logs.\n'
