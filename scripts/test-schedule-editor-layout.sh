#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

[[ "$(tr -d '[:space:]' < VERSION)" == "1.4.1" ]]
[[ -f Sources/ScheduleEditor/main.swift ]]
grep -q 'magsafe-schedule-editor' Package.swift
grep -q 'Настроить расписание' scripts/prepare-gui-daemon-transport.sh
grep -q 'magsafe-schedule-editor' install.sh
grep -q 'magsafe-schedule-editor' build-pkg.sh
grep -q 'schedule edit' install.sh
grep -q 'deferredByTemporaryState { return 0 }' scripts/prepare-schedule-sources.sh
grep -q 'delay = 2' scripts/prepare-schedule-sources.sh
grep -q 'showBatteryPercentageInStatusBar' scripts/prepare-gui-daemon-transport.sh
grep -q 'showChargeCompletionInStatusBar' scripts/prepare-gui-daemon-transport.sh
grep -q 'Показывать процент заряда' scripts/prepare-gui-daemon-transport.sh
grep -q 'Показывать время окончания зарядки' scripts/prepare-gui-daemon-transport.sh
grep -q 'readBatteryStatus' scripts/prepare-gui-daemon-transport.sh

grep -q 'boringNotchPlugImage' scripts/prepare-battery-status-icon.sh
grep -q 'boringNotchBoltImage' scripts/prepare-battery-status-icon.sh
grep -q 'drawOutlinedBoringNotchAsset' scripts/prepare-battery-status-icon.sh
grep -q 'outline: 1.15' scripts/prepare-battery-status-icon.sh
grep -q 'case charging' scripts/prepare-battery-status-icon.sh
grep -q 'case plugged' scripts/prepare-battery-status-icon.sh
grep -q 'guard cachedOnACPower == true else' scripts/prepare-battery-status-icon.sh
grep -q 'cachedOnACPower = nil' scripts/prepare-battery-status-icon.sh
grep -q 'cachedIsCharging = false' scripts/prepare-battery-status-icon.sh
grep -q 'for delay in \[0.15, 0.5, 1.0\]' scripts/prepare-battery-status-icon.sh
grep -q 'private var appearanceObservation: NSKeyValueObservation?' scripts/prepare-battery-status-icon.sh
grep -q 'statusItem.button?.observe(' scripts/prepare-battery-status-icon.sh
grep -q '\.effectiveAppearance' scripts/prepare-battery-status-icon.sh
grep -q 'performAsCurrentDrawingAppearance' scripts/prepare-battery-status-icon.sh
grep -q 'Prepared exact boring.notch plug and bolt with strict unplug normalization' scripts/prepare-battery-status-icon.sh

! grep -q 'AppleInterfaceThemeChangedNotification' scripts/prepare-battery-status-icon.sh
! grep -q 'NSApplication.didChangeEffectiveAppearanceNotification' scripts/prepare-battery-status-icon.sh
! grep -q 'drawOutlinedChargingBolt' scripts/prepare-battery-status-icon.sh
! grep -q 'plusPath' scripts/prepare-battery-status-icon.sh
! grep -q 'plugBody' scripts/prepare-battery-status-icon.sh

print "Schedule editor, exact boring.notch power assets and unplug normalization tests passed"
