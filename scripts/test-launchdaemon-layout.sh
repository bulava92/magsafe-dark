#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

[[ -f Sources/SMCDaemon/main.swift ]]
[[ -f Sources/SMCClient/main.swift ]]

grep -q 'getpeereid' Sources/SMCDaemon/main.swift
grep -q 'peerUID == consoleUID' Sources/SMCDaemon/main.swift
grep -q 'allowedValues' Sources/SMCDaemon/main.swift
! grep -q 'Process(' Sources/SMCDaemon/main.swift

zsh ./scripts/prepare-gui-daemon-transport.sh
grep -q 'private let helper = "/usr/local/libexec/magsafe-led-client"' Sources/MagSafeDark/main.swift
! grep -q '/usr/bin/sudo' Sources/MagSafeDark/main.swift
! grep -q 'magsafe-led-helper' Sources/MagSafeDark/main.swift

grep -q 'MAGSAFE_DARK_SUDO="none"' install.sh
grep -q 'magsafe-dark-cli' install.sh
grep -q 'launchctl bootstrap system' install.sh
! grep -q 'NOPASSWD' install.sh
! grep -q 'visudo' install.sh

grep -q 'MAGSAFE_DARK_SUDO="none"' build-pkg.sh
grep -q 'magsafe-dark-cli' build-pkg.sh
grep -q 'launchctl bootstrap system' build-pkg.sh
! grep -q 'NOPASSWD' build-pkg.sh
! grep -q 'visudo' build-pkg.sh

print "LaunchDaemon transport tests passed"
