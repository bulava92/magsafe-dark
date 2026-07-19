#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
zsh ./build.sh

APP_PATH="/Applications/MagSafe Dark.app"
OLD_APP_PATH="/Applications/MagSafeDark.app"
BUILD_APP_PATH="build/MagSafe Dark.app"
HELPER="/usr/local/libexec/magsafe-led-helper"
ALLOWED=(off system green orange flash blink-slow blink-fast blink-off status)

sudo install -d -m 755 /usr/local/libexec /usr/local/bin
sudo install -o root -g wheel -m 755 .build/release/magsafe-led-helper "$HELPER"
sudo install -o root -g wheel -m 755 scripts/magsafe-dark /usr/local/bin/magsafe-dark
sudo install -o root -g wheel -m 755 scripts/codex-led /usr/local/bin/codex-led

RULE="$USER ALL=(root) NOPASSWD:"
for command in "${ALLOWED[@]}"; do
  RULE+=" $HELPER $command"
  [[ "$command" != "status" ]] && RULE+=","
done
printf '%s\n' "$RULE" | sudo tee /etc/sudoers.d/magsafe-dark >/dev/null
sudo chmod 440 /etc/sudoers.d/magsafe-dark
sudo visudo -cf /etc/sudoers.d/magsafe-dark

pkill -x MagSafeDark 2>/dev/null || true
sleep 0.3
sudo rm -rf "$APP_PATH" "$OLD_APP_PATH"
sudo ditto "$BUILD_APP_PATH" "$APP_PATH"
sudo chown -R root:wheel "$APP_PATH"

open "$APP_PATH"
printf '\nInstalled as "MagSafe Dark". Commands: magsafe-dark, codex-led.\n'