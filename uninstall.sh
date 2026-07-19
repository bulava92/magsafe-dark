#!/bin/zsh
set -euo pipefail
pkill -x MagSafeDark 2>/dev/null || true
sudo rm -rf /Applications/MagSafeDark.app
sudo rm -f \
  /usr/local/libexec/magsafe-led-helper \
  /usr/local/bin/magsafe-dark \
  /usr/local/bin/codex-led \
  /etc/sudoers.d/magsafe-dark
printf 'Removed.\n'
