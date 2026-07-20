#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="Sources/MagSafeDark/main.swift"
[[ -f "$SOURCE" ]] || exit 66

python3 - "$SOURCE" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
t = p.read_text()
old = t

# Remove every property from the abandoned two-NSStatusItem implementation.
for declaration in [
    '    private var powerPlugStatusItem: NSStatusItem?\n',
    '    private weak var powerPlugImageView: NSImageView?\n',
    '    private weak var statusContentStack: NSStackView?\n',
    '    private weak var statusBatteryImageView: NSImageView?\n',
    '    private weak var statusTextField: NSTextField?\n',
    '    private weak var statusPlugImageView: NSImageView?\n',
]:
    t = t.replace(declaration, '')

property_anchor = '    private var statusItem: NSStatusItem!\n'
if property_anchor not in t:
    raise SystemExit('status item property anchor not found')
t = t.replace(
    property_anchor,
    property_anchor
    + '    private weak var statusContentStack: NSStackView?\n'
    + '    private weak var statusBatteryImageView: NSImageView?\n'
    + '    private weak var statusTextField: NSTextField?\n'
    + '    private weak var statusPlugImageView: NSImageView?\n',
    1,
)

block = r'''    private func appleBatterySymbolName(percent: Int, isCharging: Bool) -> String {
        if isCharging {
            return "battery.100percent.bolt"
        }

        switch max(0, min(100, percent)) {
        case 0...12: return "battery.0percent"
        case 13...37: return "battery.25percent"
        case 38...62: return "battery.50percent"
        case 63...87: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func configuredBatterySymbol(
        named symbolName: String,
        fillColor: NSColor
    ) -> NSImage? {
        let base = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        let palette = NSImage.SymbolConfiguration(
            paletteColors: [fillColor, NSColor.labelColor]
        )
        return NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(base.applying(palette))
    }

    private func configuredPlugSymbol() -> NSImage? {
        let base = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let symbol = NSImage(
            systemSymbolName: "powerplug.portrait.fill",
            accessibilityDescription: "Connected to power"
        ) ?? NSImage(
            systemSymbolName: "powerplug.fill",
            accessibilityDescription: "Connected to power"
        )
        symbol?.isTemplate = true
        return symbol?.withSymbolConfiguration(base)
    }

    private func installStatusContentViewIfNeeded() {
        guard statusContentStack == nil, let button = statusItem.button else { return }

        button.image = nil
        button.title = ""
        button.imagePosition = .noImage

        let batteryView = NSImageView()
        batteryView.imageScaling = .scaleNone
        batteryView.imageAlignment = .alignCenter
        batteryView.setContentHuggingPriority(.required, for: .horizontal)
        batteryView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textField = NSTextField(labelWithString: "")
        textField.font = NSFont.menuBarFont(ofSize: 0)
        textField.textColor = .labelColor
        textField.alignment = .left
        textField.lineBreakMode = .byClipping
        textField.setContentHuggingPriority(.required, for: .horizontal)
        textField.setContentCompressionResistancePriority(.required, for: .horizontal)

        let plugView = NSImageView()
        plugView.imageScaling = .scaleNone
        plugView.imageAlignment = .alignCenter
        plugView.setContentHuggingPriority(.required, for: .horizontal)
        plugView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = NSStackView(views: [batteryView, textField, plugView])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .gravityAreas
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            stack.topAnchor.constraint(equalTo: button.topAnchor),
            stack.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])

        statusContentStack = stack
        statusBatteryImageView = batteryView
        statusTextField = textField
        statusPlugImageView = plugView
    }

    private func makeBatteryStatusIcon(kind: BatteryStatusIconKind, mode: UInt8?) -> NSImage {
        let percent = max(0, min(100, cachedBatteryPercent ?? 100))
        let fillColor = bulbColor(for: mode) ?? NSColor.labelColor
        let symbolName = appleBatterySymbolName(
            percent: percent,
            isCharging: kind == .charging
        )

        guard let battery = configuredBatterySymbol(
            named: symbolName,
            fillColor: fillColor
        ) else {
            let fallback = NSImage(
                systemSymbolName: "battery.100percent",
                accessibilityDescription: nil
            ) ?? NSImage(size: NSSize(width: 22, height: 16))
            fallback.isTemplate = true
            return fallback
        }

        battery.isTemplate = false
        switch kind {
        case .battery:
            battery.accessibilityDescription = "Battery \(percent)%"
        case .charging:
            battery.accessibilityDescription = "Battery charging \(percent)%"
        case .plugged:
            battery.accessibilityDescription = "Battery connected to power \(percent)%"
        }
        return battery
    }
'''

pattern = re.compile(
    r'    private func appleBatterySymbolName\(.*?(?=    private func makeStatusBarIcon)',
    re.S,
)
t, count = pattern.subn(lambda _: block + '\n', t, count=1)
if count == 0:
    pattern = re.compile(
        r'    private func makeBatteryStatusIcon\(kind: BatteryStatusIconKind, mode: UInt8\?\) -> NSImage \{.*?\n    \}\n\n(?=    private func makeStatusBarIcon)',
        re.S,
    )
    t, count = pattern.subn(lambda _: block + '\n', t, count=1)
if count != 1:
    raise SystemExit('battery renderer anchor not found')

update = r'''    private func updateStatusIcon(mode: UInt8?, remaining: Int?) {
        installStatusContentViewIfNeeded()

        let kind: BatteryStatusIconKind
        if cachedOnACPower != true {
            kind = .battery
        } else if cachedIsCharging == true {
            kind = .charging
        } else {
            kind = .plugged
        }

        statusBatteryImageView?.image = makeBatteryStatusIcon(kind: kind, mode: mode)

        var statusParts: [String] = []
        if defaults.bool(forKey: showBatteryPercentageKey), let battery = cachedBatteryPercent {
            statusParts.append("\(battery)%")
        }
        if defaults.bool(forKey: showChargeCompletionKey),
           cachedOnACPower == true,
           cachedIsCharging == true,
           let completion = cachedChargeCompletion {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            statusParts.append(formatter.string(from: completion))
        }
        if defaults.bool(forKey: showTimerInStatusBarKey), let remaining {
            statusParts.append(formatDuration(remaining))
        }

        statusTextField?.stringValue = statusParts.joined(separator: "\u{2009}")
        statusTextField?.isHidden = statusParts.isEmpty

        let showPlug = kind == .plugged
        statusPlugImageView?.image = showPlug ? configuredPlugSymbol() : nil
        statusPlugImageView?.isHidden = !showPlug

        statusItem.button?.image = nil
        statusItem.button?.title = ""
        statusContentStack?.layoutSubtreeIfNeeded()
        if let stack = statusContentStack {
            statusItem.length = ceil(stack.fittingSize.width)
        }
    }

'''

# Remove the obsolete separate-item update call before replacing the function.
t = t.replace(
    '        updatePowerPlugStatusItem(visible: cachedOnACPower == true && cachedIsCharging != true)\n',
    '',
)
t = re.sub(
    r'    private func updateStatusIcon\(mode: UInt8\?, remaining: Int\?\) \{.*?\n    \}\n\n(?=    private func updateOpenMenu)',
    lambda _: update,
    t,
    count=1,
    flags=re.S,
)

for marker in [
    'private weak var statusContentStack: NSStackView?',
    'private weak var statusBatteryImageView: NSImageView?',
    'private weak var statusTextField: NSTextField?',
    'private weak var statusPlugImageView: NSImageView?',
    'let stack = NSStackView(views: [batteryView, textField, plugView])',
    'stack.spacing = 4',
    'statusTextField?.stringValue = statusParts.joined',
    'statusPlugImageView?.isHidden = !showPlug',
    'statusItem.length = ceil(stack.fittingSize.width)',
    'paletteColors: [fillColor, NSColor.labelColor]',
    'battery.100percent.bolt',
]:
    if marker not in t:
        raise SystemExit('missing ' + marker)

for removed in [
    'powerPlugStatusItem',
    'powerPlugImageView',
    'updatePowerPlugStatusItem',
    'NSStatusBar.system.removeStatusItem',
    'NSStatusBar.system.statusItem(withLength: 10)',
    'NSImage(size: NSSize(width: 34',
    'aspectFitRect',
    'plug.draw(',
    'battery.draw(',
    'NSBezierPath(',
]:
    if removed in t:
        raise SystemExit('obsolete separate status item remains')

if t != old:
    p.write_text(t)
PY
