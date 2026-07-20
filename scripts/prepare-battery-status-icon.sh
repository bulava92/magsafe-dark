#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
SOURCE="Sources/MagSafeDark/main.swift"

[[ -f "$SOURCE" ]] || {
  print -u2 "Missing GUI source: $SOURCE"
  exit 66
}

python3 - "$SOURCE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
original = text

text = text.replace('text("Подсвечивать колбу цветом LED", "Color the bulb using the LED color")', 'text("Подсвечивать значок цветом LED", "Color the icon using the LED color")')
text = text.replace('text("Подсвечивать батарею цветом LED", "Color the battery using the LED color")', 'text("Подсвечивать значок цветом LED", "Color the icon using the LED color")')
text = text.replace('text("Монохромная батарея", "Monochrome battery")', 'text("Чёрно-белый", "Monochrome")')
text = text.replace('#selector(useMonochrome batteryIcon)', '#selector(useMonochromeIcon)')
text = text.replace('private func useMonochrome batteryIcon()', 'private func useMonochromeIcon()')

replacement = r'''    private enum BatteryStatusIconKind {
        case battery
        case charging
        case plugged
    }

    private func statusActivityColor(mode: UInt8?) -> NSColor? {
        guard iconStyle == .actualColor else { return nil }
        return bulbColor(for: mode)
    }

    private func imageFromBase64(_ encoded: String) -> NSImage? {
        guard let data = Data(base64Encoded: encoded.filter { !$0.isWhitespace }),
              let image = NSImage(data: data) else { return nil }
        image.isTemplate = true
        return image
    }

    private func boringNotchPlugImage() -> NSImage? {
        imageFromBase64("""
        iVBORw0KGgoAAAANSUhEUgAAAC0AAABACAYAAACOcP4eAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAMYSURBVHgB7ZrBsdowEIb/vOQOueWoDkIJLoEOcCqADuwOoAPoAFKBoQKgAjsVONecFC3PZBxGWsmyLfvN+JvZN29GXuv3yrJWK4BmRMq2ynJlsrJSWaYsZvzmypLquvLFj+4n0AOi6kBaLNeIT2pCOdtWD9cJC8dO65ZUAq4N/eihBVoiPATXBfj6sRH/DB6K1Df44TvU5PdH2RkeLOEXqS6sBPPQbzCzMjUkSYKyLCGlRJZlEELAheVyiev1+vDL8xxxHJsuJcExPNBOou12K19RAuR8Pmejt1gspA71ICafPTzQ3kxFWNu5ihorerfbaf1Op5PJJzMJ414PLSqi8MHkN5vN0JTGosfAJDoUJtERhocmgdA1vGkuPIKZuQGhnId0JK8NddEC79/mJcaDUJbi5Zv9VmvM0FNe2wExasKfomkIBMZNXBm+4F1szF1NC4NtUaFFgstBTIsI3ffpVxQFLFBwD/TPDoald71eP/KKkKgE7JGnwJwSRCQ60zVuNhs5FJTfMMI39E4vdOOwWq0wFPTKMGnrdxKtfVnVk2JImPnxdbTLOJP9zaaEKRST6FB8WNG/dQ0OS2qvMP0XoxV9v99NTb9I9EXXcrlcMCS3283YRKK1refzGUNBo8z0X9AfWq+1yQllXENAyRrMFdV/5LqLoiiSoaFUWOUdTqWy1BTt4/EoQ2Ipr4m6aMr0tMVzKiyG2ghQvY8R/F+UrdGm4epb+OFwYAuYMOxh52COHEi4qi3LPrBEmGwHhoXFWaZpKruCRo8mu6XPHA5sbMKpI1Oduolg5itRFyzgSOoivGfBJQz711bCfRcf26lBFWHvTeoSzOT0LTNY6hoZOjoAPeo6oIj5AM+vxBOXTUCh7CfCsHG5aNpuhWISHYpJdCgm0aFwFT3K2ogNbZ5NW7GmKep+v2+VNzdFu4ekFNV1K0Y7HyYlPbkK+QR3DjD8RIjOSJR49tjOUoAhflR9dEoES37dwnp5NZ4YzxxbWu/n8QegU8EpAtFFxGlixwiMgF/USWyKFj+GbfL14Ijgtq+7wVBabsJfqBHoqpScek8AAAAASUVORK5CYII=
        """)
    }

    private func boringNotchBoltImage() -> NSImage? {
        imageFromBase64("""
        iVBORw0KGgoAAAANSUhEUgAAAC0AAABACAYAAACOcP4eAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAMcSURBVHgBzZqBdeIwEEQn18C5BJVACb4OKEFUAB2YDuAqMB1ABy7B14HpgBJ03sDeOUSStbYs+b+3j+QRxxNpZyQrAGko+qr6avsyr3r0VfdVYoXs8RRoPEXiFVYCiTGB1WEFwqkdjLAaZGQPuWCuEhlQGO9hX92QGIVnb1oFbTYb07ateTwe5nA4uEQ/kJirQ4hRSpmu6wxDwuEe7WRULhFFUXwRzCCzaO0RYE6n0zfBdV1nbQ8Fj/GqqjI2ttttNiMqeIxXlqVVMLUK3DOjsTDBxgtsjQ4LU0FoPIaiz3FtjQXREBqPoZz2XLvBQihMMB6jtU7eGgoTjDeEeh2JDTjJeMztdvO1hsICVJhoPMaTzQ0WQGOi8ZjU2awww3hMymWbHkg7l2DK21A82czJMSx6ACb/aEzo9VnGC2yNseogaJ/K98tCBROebJZUNSZ4i5nGG+LJZmltXYIVIhiPaZomlmA2bfEuOJrxmEit8WW0P95EX11T0E8x+lH7fJVwv98hha7Z7Xaua38Pv6kQyXgx8OT67cdLMI3uEQ5644lHeEF+8hfOPpYaLwZ0vOBJnDMJ1ohovBh4NlZUJYlubG9KVryYHI9Hn+COW8OayWSE1Fyv17G40yza+gOpoVkdWTnPGGAd6cvlYlIxYjyqdij449XTJSz0z3yQ0psI+/1edA0tJP0gud6+9/Xr9fqPA+Isr59FRwQSRoxHZT1W8O43JEVTLCHAeAd4oL9mzum9OHGkxvMJ7+aIDs11qfHGUHjuQcTiQw5qmJHtaocZZyA08uVbacxsjanGm4O23YgOa0KYa7yptLab0XSPEct4UpTrhvQc6CPAeB0WosbEbF7SeGN0tpuez2ev4BzGY0pMyOaA44MjFsTaGr5szmU8poAwm3Maj9Gum5M4G55/1i9uPKaBIJtzGo9xtoYtm3MbjykRmM25jTcq+j011mC8IRubCNogDU2Yc8Wz4expGlkSS6OOzMaz0cAvKrvxbJSYJjiZ8VycIRNM++4CKyBUeIOVCGY03A+9LRJ8lIf4wDQoERT+j+ifVyXhLwtlKgvlWzgBAAAAAElFTkSuQmCC
        """)
    }

    private func tintedSymbol(_ source: NSImage, size: NSSize, color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1.0)
        color.setFill()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func drawOutlinedBoringNotchAsset(_ source: NSImage, in rect: NSRect, outline: CGFloat) {
        let black = tintedSymbol(source, size: rect.size, color: .black)
        for offset in [
            NSPoint(x: -outline, y: 0), NSPoint(x: outline, y: 0),
            NSPoint(x: 0, y: -outline), NSPoint(x: 0, y: outline),
            NSPoint(x: -outline, y: -outline), NSPoint(x: -outline, y: outline),
            NSPoint(x: outline, y: -outline), NSPoint(x: outline, y: outline)
        ] {
            black.draw(in: rect.offsetBy(dx: offset.x, dy: offset.y))
        }
        tintedSymbol(source, size: rect.size, color: .white).draw(in: rect)
    }

    private func makeBatteryStatusIcon(kind: BatteryStatusIconKind, mode: UInt8?) -> NSImage {
        let size = NSSize(width: 24, height: 18)
        let image = NSImage(size: size)
        let appearance = statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance

        appearance.performAsCurrentDrawingAppearance {
            image.lockFocus()
            defer { image.unlockFocus() }

            let outlineColor = NSColor.labelColor
            let bodyRect = NSRect(x: 1.25, y: 3.2, width: 19.0, height: 11.6)
            let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 2.7, yRadius: 2.7)
            bodyPath.lineWidth = 1.45

            let innerRect = bodyRect.insetBy(dx: 1.85, dy: 1.85)
            let fillColor: NSColor?
            switch kind {
            case .charging, .plugged:
                fillColor = statusActivityColor(mode: mode) ?? NSColor.systemGreen
            case .battery:
                fillColor = statusActivityColor(mode: mode)
            }

            if let fillColor {
                let percent: CGFloat = kind == .battery
                    ? CGFloat(max(0, min(100, cachedBatteryPercent ?? 100))) / 100.0
                    : 1.0
                let fillWidth = innerRect.width * percent
                if fillWidth > 0 {
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(roundedRect: innerRect, xRadius: 1.55, yRadius: 1.55).addClip()
                    fillColor.setFill()
                    NSBezierPath(
                        roundedRect: NSRect(x: innerRect.minX, y: innerRect.minY, width: fillWidth, height: innerRect.height),
                        xRadius: min(1.55, fillWidth / 2.0),
                        yRadius: 1.55
                    ).fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
            }

            outlineColor.setStroke()
            bodyPath.stroke()

            let terminalPath = NSBezierPath(roundedRect: NSRect(x: 21.05, y: 6.45, width: 1.7, height: 5.1), xRadius: 0.85, yRadius: 0.85)
            terminalPath.lineWidth = 1.35
            terminalPath.stroke()

            switch kind {
            case .battery:
                break
            case .charging:
                if let bolt = boringNotchBoltImage() {
                    drawOutlinedBoringNotchAsset(bolt, in: NSRect(x: 7.35, y: 1.55, width: 8.7, height: 15.5), outline: 1.05)
                }
            case .plugged:
                if let plug = boringNotchPlugImage() {
                    drawOutlinedBoringNotchAsset(plug, in: NSRect(x: 7.15, y: 1.25, width: 9.1, height: 16.2), outline: 1.15)
                }
            }
        }

        image.isTemplate = false
        switch kind {
        case .battery:
            image.accessibilityDescription = "Battery, MagSafe LED: \(modeName(mode))"
        case .charging:
            image.accessibilityDescription = "Battery charging, MagSafe LED: \(modeName(mode))"
        case .plugged:
            image.accessibilityDescription = "Connected to power, MagSafe LED: \(modeName(mode))"
        }
        return image
    }

    private func makeStatusBarIcon(mode: UInt8?) -> NSImage {
        guard cachedOnACPower == true else {
            return makeBatteryStatusIcon(kind: .battery, mode: mode)
        }
        if cachedIsCharging == true {
            return makeBatteryStatusIcon(kind: .charging, mode: mode)
        }
        return makeBatteryStatusIcon(kind: .plugged, mode: mode)
    }

    private func updateStatusIcon(mode: UInt8?, remaining: Int?) {
        statusItem.button?.image = makeStatusBarIcon(mode: mode)
        statusItem.button?.imagePosition = .imageLeading

        var statusParts: [String] = []
        if defaults.bool(forKey: showBatteryPercentageKey), let battery = cachedBatteryPercent {
            statusParts.append("\(battery)%")
        }
        if defaults.bool(forKey: showChargeCompletionKey), cachedOnACPower == true, cachedIsCharging == true, let completion = cachedChargeCompletion {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            statusParts.append(formatter.string(from: completion))
        }
        if defaults.bool(forKey: showTimerInStatusBarKey), let remaining {
            statusParts.append(formatDuration(remaining))
        }
        statusItem.button?.title = statusParts.isEmpty ? "" : "\u{2009}" + statusParts.joined(separator: "\u{2009}")
    }

'''

patterns = [
    re.compile(r'    private enum BatteryStatusIconKind \{.*?\n    private func updateStatusIcon\(mode: UInt8\?, remaining: Int\?\) \{.*?\n    \}\n\n(?=    private func updateOpenMenu)', re.S),
    re.compile(r'    private func svgImage\(.*?\n    private func updateStatusIcon\(mode: UInt8\?, remaining: Int\?\) \{.*?\n    \}\n\n(?=    private func updateOpenMenu)', re.S),
    re.compile(r'    private func svgTemplateImage\(.*?\n    private func updateStatusIcon\(mode: UInt8\?, remaining: Int\?\) \{.*?\n    \}\n\n(?=    private func updateOpenMenu)', re.S),
    re.compile(r'    private func makeCompactPowerSymbol\(\) -> NSImage\? \{.*?\n    private func updateStatusIcon\(mode: UInt8\?, remaining: Int\?\) \{.*?\n    \}\n\n(?=    private func updateOpenMenu)', re.S),
    re.compile(r'    private func batterySymbolName\(for percentage: Int\?\) -> String \{.*?\n    private func updateStatusIcon\(mode: UInt8\?, remaining: Int\?\) \{.*?\n    \}\n\n(?=    private func updateOpenMenu)', re.S),
    re.compile(r'    private func updateStatusIcon\(mode: UInt8\?, remaining: Int\?\) \{.*?\n    \}\n\n(?=    private func updateOpenMenu)', re.S),
]

count = 0
for pattern in patterns:
    text, count = pattern.subn(lambda _: replacement, text, count=1)
    if count == 1:
        break
if count != 1:
    raise SystemExit('Could not replace status bar icon implementation')

text = text.replace('    private var appearanceObserver: NSObjectProtocol?\n', '')
if 'private var appearanceObservation: NSKeyValueObservation?' not in text:
    text = text.replace(
        '    private var refreshTimer: Timer?\n',
        '    private var refreshTimer: Timer?\n    private var appearanceObservation: NSKeyValueObservation?\n',
        1,
    )

if 'installAppearanceObserver()' not in text:
    text = text.replace('        statusItem.menu = menu\n', '        statusItem.menu = menu\n        installAppearanceObserver()\n', 1)

text = re.sub(
    r'    private func installAppearanceObserver\(\) \{.*?\n    \}\n\n(?=    private func registerSystemNotifications)',
    '', text, count=1, flags=re.S,
)

appearance_method = r'''    private func installAppearanceObserver() {
        appearanceObservation = statusItem.button?.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            guard let self else { return }
            self.updateStatusIcon(mode: self.cachedMode, remaining: self.cachedTimerRemaining)
            self.rebuildMenu()
        }
    }

'''
anchor = '    private func registerSystemNotifications() {'
if anchor not in text:
    raise SystemExit('Could not find system notification registration anchor')
text = text.replace(anchor, appearance_method + anchor, 1)

text = re.sub(
    r'    @objc private func powerStateChanged\(\) \{.*?\n    \}',
    '''    @objc private func powerStateChanged() {
        cachedOnACPower = nil
        cachedIsCharging = false
        cachedChargeCompletion = nil
        updateStatusIcon(mode: cachedMode, remaining: cachedTimerRemaining)
        requestRefresh(force: true)
        for delay in [0.15, 0.5, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.requestRefresh(force: true)
            }
        }
    }''',
    text, count=1, flags=re.S,
)

text = re.sub(
    r'\n        let chargingState = item\(text\("(?:Показывать состояние зарядки|Автоматически выбирать батарею или вилку)".*?\n        settings\.addItem\(chargingState\)\n',
    '\n', text, count=1, flags=re.S,
)
text = re.sub(r'    @objc private func toggleChargingState\(\) \{.*?\n    \}\n\n', '', text, count=1, flags=re.S)

for marker in [
    'boringNotchPlugImage', 'boringNotchBoltImage', 'drawOutlinedBoringNotchAsset',
    'outline: 1.15', 'case charging', 'case plugged',
    'guard cachedOnACPower == true else', 'cachedOnACPower = nil',
    'cachedIsCharging = false', 'for delay in [0.15, 0.5, 1.0]',
    'private var appearanceObservation: NSKeyValueObservation?',
    'statusItem.button?.observe(', r'\.effectiveAppearance',
    'installAppearanceObserver()', 'performAsCurrentDrawingAppearance',
    'Подсвечивать значок цветом LED', 'NSSize(width: 24, height: 18)',
]:
    if marker not in text:
        raise SystemExit(f'Missing battery status icon marker: {marker}')

for removed in [
    'AppleInterfaceThemeChangedNotification',
    'private var appearanceObserver: NSObjectProtocol?',
    'NSApplication.didChangeEffectiveAppearanceNotification',
    'resolvedColor(with:', 'drawOutlinedChargingBolt', 'plusPath', 'plugBody',
    'lightbulb', 'powerplug.fill', 'makeCompactPowerSymbol', 'coloredPlugIcon',
    'svgImage', 'svgTemplateImage', 'Автоматически выбирать батарею или вилку',
]:
    if removed in text:
        raise SystemExit(f'Obsolete icon code remains: {removed}')

if text != original:
    path.write_text(text)
    print('Prepared exact boring.notch plug and bolt with strict unplug normalization')
else:
    print('Exact boring.notch plug and bolt with strict unplug normalization already prepared')
PY
