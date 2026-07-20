#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION_VALUE" == <->.<->.<-> ]] || { print -u2 "Invalid VERSION: $VERSION_VALUE"; exit 1; }

BUILD_PACKAGE=0
if [[ "${1:-}" == "--package" ]]; then
  BUILD_PACKAGE=1
elif (( $# > 0 )); then
  print -u2 "Usage: zsh ./scripts/check-release.sh [--package]"
  exit 64
fi

zsh -n install.sh build.sh build-pkg.sh uninstall.sh
zsh -n \
  scripts/magsafe-dark \
  scripts/codex-led \
  scripts/prepare-menu-ux.sh \
  scripts/prepare-status-glyph-style.sh \
  scripts/prepare-gui-daemon-transport.sh \
  scripts/prepare-battery-status-icon.sh \
  scripts/prepare-native-power-status.sh \
  scripts/prepare-boring-battery-design.sh \
  scripts/prepare-schedule-sources.sh \
  scripts/test-core.sh \
  scripts/test-schedule-core.sh \
  scripts/test-schedule-editor-layout.sh \
  scripts/test-codex-led.sh \
  scripts/test-cli-settings.sh \
  scripts/test-helper-interface.sh \
  scripts/test-daemon-client.sh \
  scripts/test-launchdaemon-layout.sh \
  scripts/validate-pkg.sh \
  scripts/sign-and-notarize.sh \
  scripts/check-release.sh

zsh ./scripts/test-core.sh
zsh ./scripts/test-schedule-core.sh
zsh ./scripts/test-schedule-editor-layout.sh
zsh ./scripts/test-codex-led.sh
zsh ./scripts/test-cli-settings.sh
zsh ./scripts/test-launchdaemon-layout.sh
zsh ./scripts/prepare-menu-ux.sh
zsh ./scripts/prepare-native-power-status.sh
zsh ./scripts/prepare-status-glyph-style.sh
swift build
swift build -c release
zsh ./scripts/test-helper-interface.sh
zsh ./scripts/test-daemon-client.sh

grep -q 'import IOKit.ps' Sources/MagSafeDark/main.swift
grep -q 'IOPSNotificationCreateRunLoopSource' Sources/MagSafeDark/main.swift
grep -q 'IOPSCopyPowerSourcesInfo' Sources/MagSafeDark/main.swift
grep -q 'IOPSCopyPowerSourcesList' Sources/MagSafeDark/main.swift
grep -q 'IOPSGetPowerSourceDescription' Sources/MagSafeDark/main.swift
grep -q 'private func refreshNativePowerState' Sources/MagSafeDark/main.swift
grep -q 'kIOPSTimeToFullChargeKey' Sources/MagSafeDark/main.swift
grep -q 'description\["Is Finishing Charge"\]' Sources/MagSafeDark/main.swift
grep -q 'reportsCharging && !isFinishingCharge && belowFullCapacity && hasRemainingChargeTime' Sources/MagSafeDark/main.swift
grep -q 'lower.contains("finishing charge")' Sources/MagSafeDark/main.swift
grep -q 'guard cachedOnACPower == true' Sources/MagSafeDark/main.swift
grep -q 'private var appearanceObservation: NSKeyValueObservation?' Sources/MagSafeDark/main.swift
grep -q 'statusItem.button?.observe(' Sources/MagSafeDark/main.swift
grep -q '\.effectiveAppearance' Sources/MagSafeDark/main.swift

grep -q 'private weak var statusContentStack: NSStackView?' Sources/MagSafeDark/main.swift
grep -q 'private weak var statusBatteryImageView: NSImageView?' Sources/MagSafeDark/main.swift
grep -q 'private weak var statusTextField: NSTextField?' Sources/MagSafeDark/main.swift
grep -q 'private weak var statusPlugImageView: NSImageView?' Sources/MagSafeDark/main.swift
grep -q 'let stack = NSStackView(views: \[batteryView, textField, plugView\])' Sources/MagSafeDark/main.swift
grep -q 'stack.spacing = 4' Sources/MagSafeDark/main.swift
grep -q 'statusTextField?.stringValue = statusParts.joined' Sources/MagSafeDark/main.swift
grep -q 'statusPlugImageView?.isHidden = !showPlug' Sources/MagSafeDark/main.swift
grep -q 'statusItem.length = ceil(stack.fittingSize.width)' Sources/MagSafeDark/main.swift
grep -q 'systemSymbolName: "powerplug.portrait.fill"' Sources/MagSafeDark/main.swift
grep -q 'systemSymbolName: "powerplug.fill"' Sources/MagSafeDark/main.swift

grep -q 'private func appleBatterySymbolName' Sources/MagSafeDark/main.swift
grep -q 'battery.0percent' Sources/MagSafeDark/main.swift
grep -q 'battery.25percent' Sources/MagSafeDark/main.swift
grep -q 'battery.50percent' Sources/MagSafeDark/main.swift
grep -q 'battery.75percent' Sources/MagSafeDark/main.swift
grep -q 'battery.100percent' Sources/MagSafeDark/main.swift
grep -q 'battery.100percent.bolt' Sources/MagSafeDark/main.swift
grep -q 'if symbolName == "battery.100percent.bolt"' Sources/MagSafeDark/main.swift
grep -q 'paletteColors: paletteColors' Sources/MagSafeDark/main.swift
grep -q 'NSColor.secondaryLabelColor' Sources/MagSafeDark/main.swift
grep -q 'fillColor,' Sources/MagSafeDark/main.swift
grep -q 'base.applying(palette)' Sources/MagSafeDark/main.swift
grep -q 'bulbColor(for: mode)' Sources/MagSafeDark/main.swift
grep -q 'battery.isTemplate = false' Sources/MagSafeDark/main.swift

grep -q 'private enum StatusGlyphStyle: String { case battery, lightbulb }' Sources/MagSafeDark/main.swift
grep -q 'let symbolName = "lightbulb.led.fill"' Sources/MagSafeDark/main.swift
grep -q 'Значок состояния' Sources/MagSafeDark/main.swift
grep -q 'Лампочка' Sources/MagSafeDark/main.swift
grep -q 'useBatteryStatusGlyph' Sources/MagSafeDark/main.swift
grep -q 'useLightbulbStatusGlyph' Sources/MagSafeDark/main.swift
grep -Fq 'let showPlug = defaults.bool(forKey: showChargingStateKey) && kind == .plugged' Sources/MagSafeDark/main.swift
! grep -Fq 'let showPlug = kind == .plugged' Sources/MagSafeDark/main.swift
! grep -q 'statusGlyphStyle == .battery && kind == .plugged' Sources/MagSafeDark/main.swift

grep -q 'Вернуть штатный режим' Sources/MagSafeDark/main.swift
grep -q 'Выключить индикатор' Sources/MagSafeDark/main.swift
grep -q 'Отменить ручное управление' Sources/MagSafeDark/main.swift
grep -q 'Показывать подключение к питанию' Sources/MagSafeDark/main.swift
grep -q 'Расписание включено' Sources/MagSafeDark/main.swift
grep -q 'result.state = expectedValue(for: mode) == cachedMode' Sources/MagSafeDark/main.swift
grep -q 'ruleIsActiveNow' Sources/ScheduleEditor/main.swift
grep -q 'сохранять последний режим' Sources/ScheduleEditor/main.swift

! grep -q 'powerPlugStatusItem' Sources/MagSafeDark/main.swift
! grep -q 'powerPlugImageView' Sources/MagSafeDark/main.swift
! grep -q 'updatePowerPlugStatusItem' Sources/MagSafeDark/main.swift
! grep -q 'NSStatusBar.system.removeStatusItem' Sources/MagSafeDark/main.swift
! grep -q 'NSStatusBar.system.statusItem(withLength: 10)' Sources/MagSafeDark/main.swift
! grep -q 'NSStatusItem.squareLength' Sources/MagSafeDark/main.swift
! grep -q 'NSImage(size: NSSize(width: 34' Sources/MagSafeDark/main.swift
! grep -q 'aspectFitRect' Sources/MagSafeDark/main.swift
! grep -q 'plug.draw(' Sources/MagSafeDark/main.swift
! grep -q 'battery.draw(' Sources/MagSafeDark/main.swift
! grep -q 'drawBatteryGlyph' Sources/MagSafeDark/main.swift
! grep -q 'NSBezierPath(' Sources/MagSafeDark/main.swift
! grep -q 'BoringBatteryStatusView' Sources/MagSafeDark/main.swift
! grep -q 'NSHostingView(rootView:' Sources/MagSafeDark/main.swift
! grep -q 'drawAdaptivePowerGlyph' Sources/MagSafeDark/main.swift
! grep -q 'drawAdaptiveBoringNotchGlyph' Sources/MagSafeDark/main.swift
! grep -q 'tintedTemplateImage' Sources/MagSafeDark/main.swift
! grep -q 'drawOutlinedBoringNotchAsset' Sources/MagSafeDark/main.swift
! grep -q 'AppleInterfaceThemeChangedNotification' Sources/MagSafeDark/main.swift
! grep -q 'NSApplication.didChangeEffectiveAppearanceNotification' Sources/MagSafeDark/main.swift
! grep -q '.now() + 0.15' Sources/MagSafeDark/main.swift
! grep -q '.now() + 0.25' Sources/MagSafeDark/main.swift
! grep -q '.now() + 0.5' Sources/MagSafeDark/main.swift
! grep -q '.now() + 1.0' Sources/MagSafeDark/main.swift

if (( BUILD_PACKAGE )); then
  zsh ./build-pkg.sh "$VERSION_VALUE"
  zsh ./scripts/validate-pkg.sh "build/MagSafeDark-${VERSION_VALUE}-unsigned.pkg"
fi
print "Local release checks passed for $VERSION_VALUE"
