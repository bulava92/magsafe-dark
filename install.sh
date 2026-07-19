#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
./build.sh

sudo install -d -m 755 /usr/local/libexec
sudo install -o root -g wheel -m 755 \
  .build/release/magsafe-led-helper \
  /usr/local/libexec/magsafe-led-helper

printf '%s\n' "$USER ALL=(root) NOPASSWD: /usr/local/libexec/magsafe-led-helper off, /usr/local/libexec/magsafe-led-helper system, /usr/local/libexec/magsafe-led-helper green, /usr/local/libexec/magsafe-led-helper orange, /usr/local/libexec/magsafe-led-helper status" \
  | sudo tee /etc/sudoers.d/magsafe-dark >/dev/null
sudo chmod 440 /etc/sudoers.d/magsafe-dark
sudo visudo -cf /etc/sudoers.d/magsafe-dark

pkill -x MagSafeDark 2>/dev/null || true
sleep 0.3

sudo rm -rf /Applications/MagSafeDark.app
sudo ditto build/MagSafeDark.app /Applications/MagSafeDark.app
sudo chown -R root:wheel /Applications/MagSafeDark.app

open /Applications/MagSafeDark.app
printf '\nInstalled. Use the lightbulb icon in the menu bar.\n'
