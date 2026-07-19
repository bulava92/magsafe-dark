#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
./build.sh

APP_PATH="/Applications/MagSafe Dark.app"
OLD_APP_PATH="/Applications/MagSafeDark.app"
BUILD_APP_PATH="build/MagSafe Dark.app"

sudo install -d -m 755 /usr/local/libexec /usr/local/bin
sudo install -o root -g wheel -m 755 \
  .build/release/magsafe-led-helper \
  /usr/local/libexec/magsafe-led-helper
sudo install -o root -g wheel -m 755 \
  scripts/magsafe-dark \
  /usr/local/bin/magsafe-dark
sudo install -o root -g wheel -m 755 \
  scripts/codex-led \
  /usr/local/bin/codex-led

printf '%s\n' "$USER ALL=(root) NOPASSWD: /usr/local/libexec/magsafe-led-helper off, /usr/local/libexec/magsafe-led-helper system, /usr/local/libexec/magsafe-led-helper green, /usr/local/libexec/magsafe-led-helper orange, /usr/local/libexec/magsafe-led-helper status" \
  | sudo tee /etc/sudoers.d/magsafe-dark >/dev/null
sudo chmod 440 /etc/sudoers.d/magsafe-dark
sudo visudo -cf /etc/sudoers.d/magsafe-dark

pkill -x MagSafeDark 2>/dev/null || true
sleep 0.3

sudo rm -rf "$APP_PATH" "$OLD_APP_PATH"
sudo ditto "$BUILD_APP_PATH" "$APP_PATH"
sudo chown -R root:wheel "$APP_PATH"

open "$APP_PATH"
printf '\nInstalled as "MagSafe Dark". Commands: magsafe-dark, codex-led.\n'
