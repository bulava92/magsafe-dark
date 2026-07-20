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

if 'import IOKit.ps' not in text:
    text = text.replace('import Foundation\n', 'import Foundation\nimport IOKit.ps\n', 1)

# Keep the original boring.notch PNG pixels. They already contain the intended
# black edge and antialiasing; template tinting destroys that geometry.
text = text.replace('        image.isTemplate = true\n        return image\n', '        image.isTemplate = false\n        return image\n', 1)

asset_renderer = r'''    private func drawBoringNotchAsset(_ source: NSImage, centeredIn frame: NSRect) {
        let sourceSize = source.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return }
        let scale = min(frame.width / sourceSize.width, frame.height / sourceSize.height)
        let drawSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let drawRect = NSRect(
            x: frame.midX - drawSize.width / 2.0,
            y: frame.midY - drawSize.height / 2.0,
            width: drawSize.width,
            height: drawSize.height
        )
        source.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

'''
text, count = re.subn(
    r'    private func tintedSymbol\(.*?\n    private func makeBatteryStatusIcon',
    lambda _: asset_renderer + '    private func makeBatteryStatusIcon',
    text,
    count=1,
    flags=re.S,
)
if count != 1 and 'private func drawBoringNotchAsset' not in text:
    raise SystemExit('Could not replace power glyph renderer')

text = re.sub(
    r'if let bolt = boringNotchBoltImage\(\) \{\s*drawOutlinedBoringNotchAsset\(bolt, in: NSRect\([^\n]+\), outline: [^)]+\)\s*\}',
    'if let bolt = boringNotchBoltImage() {\n                    drawBoringNotchAsset(bolt, centeredIn: NSRect(x: 2.25, y: 0.5, width: 17.0, height: 17.0))\n                }',
    text,
    count=1,
    flags=re.S,
)
text = re.sub(
    r'if let plug = boringNotchPlugImage\(\) \{\s*drawOutlinedBoringNotchAsset\(plug, in: NSRect\([^\n]+\), outline: [^)]+\)\s*\}',
    'if let plug = boringNotchPlugImage() {\n                    drawBoringNotchAsset(plug, centeredIn: NSRect(x: 2.25, y: 0.5, width: 17.0, height: 17.0))\n                }',
    text,
    count=1,
    flags=re.S,
)

# Charging is impossible without confirmed AC power.
text = re.sub(
    r'    private func makeStatusBarIcon\(mode: UInt8\?\) -> NSImage \{.*?\n    \}',
    '''    private func makeStatusBarIcon(mode: UInt8?) -> NSImage {
        guard cachedOnACPower == true else {
            return makeBatteryStatusIcon(kind: .battery, mode: mode)
        }
        if cachedIsCharging == true {
            return makeBatteryStatusIcon(kind: .charging, mode: mode)
        }
        return makeBatteryStatusIcon(kind: .plugged, mode: mode)
    }''',
    text,
    count=1,
    flags=re.S,
)

if 'private var powerSourceRunLoopSource: CFRunLoopSource?' not in text:
    text = text.replace(
        '    private var appearanceObservation: NSKeyValueObservation?\n',
        '    private var appearanceObservation: NSKeyValueObservation?\n    private var powerSourceRunLoopSource: CFRunLoopSource?\n',
        1,
    )

if 'installNativePowerSourceObserver()' not in text:
    text = text.replace(
        '        installAppearanceObserver()\n',
        '        installAppearanceObserver()\n        installNativePowerSourceObserver()\n',
        1,
    )

native_methods = r'''    private func installNativePowerSourceObserver() {
        refreshNativePowerState()
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let owner = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            owner.refreshNativePowerState()
        }, context)?.takeRetainedValue() else { return }
        powerSourceRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func refreshNativePowerState() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return }

        var onACPower = false
        var isCharging = false
        var batteryPercent: Int?

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let state = description[kIOPSPowerSourceStateKey as String] as? String,
               state == kIOPSACPowerValue {
                onACPower = true
            }
            if let charging = description[kIOPSIsChargingKey as String] as? Bool {
                isCharging = isCharging || charging
            }
            if let current = description[kIOPSCurrentCapacityKey as String] as? Int,
               let maximum = description[kIOPSMaxCapacityKey as String] as? Int,
               maximum > 0 {
                batteryPercent = Int((Double(current) / Double(maximum) * 100.0).rounded())
            }
        }

        if !onACPower { isCharging = false }
        cachedOnACPower = onACPower
        cachedIsCharging = isCharging
        if let batteryPercent { cachedBatteryPercent = batteryPercent }
        if !isCharging { cachedChargeCompletion = nil }
        updateStatusIcon(mode: cachedMode, remaining: cachedTimerRemaining)
    }

'''
if 'private func installNativePowerSourceObserver()' not in text:
    anchor = '    private func registerSystemNotifications() {'
    if anchor not in text:
        raise SystemExit('Could not find notification registration anchor')
    text = text.replace(anchor, native_methods + anchor, 1)

# Remove the delayed power-source observer and delayed refresh path. The native
# IOPS callback above is the source of truth for the status icon.
text = re.sub(
    r'\n        DistributedNotificationCenter\.default\(\)\.addObserver\(self, selector: #selector\(powerStateChanged\), name: NSNotification\.Name\("com\.apple\.system\.powersources\.source"\), object: nil\)',
    '',
    text,
    count=1,
)
text = re.sub(
    r'    @objc private func powerStateChanged\(\) \{.*?\n    \}\n',
    '',
    text,
    count=1,
    flags=re.S,
)
# The screen-wake notification previously referenced the removed method.
text = text.replace(
    'center.addObserver(self, selector: #selector(powerStateChanged), name: NSWorkspace.screensDidWakeNotification, object: nil)',
    'center.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)',
)

for marker in [
    'import IOKit.ps',
    'IOPSNotificationCreateRunLoopSource',
    'IOPSCopyPowerSourcesInfo',
    'IOPSCopyPowerSourcesList',
    'IOPSGetPowerSourceDescription',
    'drawBoringNotchAsset',
    'image.isTemplate = false',
    'guard cachedOnACPower == true else',
    '#selector(systemDidWake), name: NSWorkspace.screensDidWakeNotification',
]:
    if marker not in text:
        raise SystemExit(f'Missing native power marker: {marker}')

for removed in [
    'drawOutlinedBoringNotchAsset',
    'tintedSymbol(',
    '#selector(powerStateChanged)',
    '.now() + 0.15',
    '.now() + 0.25',
    '.now() + 0.5',
    '.now() + 1.0',
]:
    if removed in text:
        raise SystemExit(f'Obsolete delayed or distorted power code remains: {removed}')

if text != original:
    path.write_text(text)
    print('Prepared native power callbacks and original boring.notch glyph rendering')
else:
    print('Native power callbacks and original boring.notch glyph rendering already prepared')
PY