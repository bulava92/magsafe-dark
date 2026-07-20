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

# pmset reports "finishing charge" at 100% with 0:00 remaining. That is not an
# active charge for UI purposes: show the plug and hide completion time.
old_pmset_logic = '''        let isCharging: Bool?
        if lower.contains("not charging") || lower.contains("charged") { isCharging = false }
        else if lower.contains("charging") || lower.contains("finishing charge") { isCharging = true }
        else if onACPower == false { isCharging = false }
        else { isCharging = nil }
'''
new_pmset_logic = '''        let isCharging: Bool?
        if percentage == 100 ||
           lower.contains("not charging") ||
           lower.contains("charged") ||
           lower.contains("finishing charge") {
            isCharging = false
        } else if lower.contains("charging") {
            isCharging = true
        } else if onACPower == false {
            isCharging = false
        } else {
            isCharging = nil
        }
'''
if old_pmset_logic in text:
    text = text.replace(old_pmset_logic, new_pmset_logic, 1)
elif 'lower.contains("finishing charge") {' not in text:
    raise SystemExit('Could not update pmset charging-state logic')

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
        var reportsCharging = false
        var isFinishingCharge = false
        var batteryPercent: Int?
        var timeToFullChargeMinutes: Int?

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let state = description[kIOPSPowerSourceStateKey as String] as? String,
               state == kIOPSACPowerValue {
                onACPower = true
            }
            if let charging = description[kIOPSIsChargingKey as String] as? Bool {
                reportsCharging = reportsCharging || charging
            }
            if let finishing = description["Is Finishing Charge"] as? Bool {
                isFinishingCharge = isFinishingCharge || finishing
            } else if let finishing = description["Is Finishing Charge"] as? Int {
                isFinishingCharge = isFinishingCharge || finishing != 0
            }
            if let minutes = description[kIOPSTimeToFullChargeKey as String] as? Int {
                timeToFullChargeMinutes = minutes
            }
            if let current = description[kIOPSCurrentCapacityKey as String] as? Int,
               let maximum = description[kIOPSMaxCapacityKey as String] as? Int,
               maximum > 0 {
                batteryPercent = Int((Double(current) / Double(maximum) * 100.0).rounded())
            }
        }

        let hasRemainingChargeTime = (timeToFullChargeMinutes ?? 0) > 0
        let belowFullCapacity = (batteryPercent ?? 0) < 100
        let isCharging = onACPower && reportsCharging && !isFinishingCharge && belowFullCapacity && hasRemainingChargeTime

        cachedOnACPower = onACPower
        cachedIsCharging = isCharging
        if let batteryPercent { cachedBatteryPercent = batteryPercent }
        if isCharging, let minutes = timeToFullChargeMinutes, minutes > 0 {
            cachedChargeCompletion = Date().addingTimeInterval(TimeInterval(minutes * 60))
        } else {
            cachedChargeCompletion = nil
        }
        updateStatusIcon(mode: cachedMode, remaining: cachedTimerRemaining)
    }

'''
text, replaced_native = re.subn(
    r'    private func installNativePowerSourceObserver\(\) \{.*?\n    private func registerSystemNotifications\(\) \{',
    lambda _: native_methods + '    private func registerSystemNotifications() {',
    text,
    count=1,
    flags=re.S,
)
if replaced_native == 0:
    anchor = '    private func registerSystemNotifications() {'
    if anchor not in text:
        raise SystemExit('Could not find notification registration anchor')
    text = text.replace(anchor, native_methods + anchor, 1)

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
    'kIOPSTimeToFullChargeKey',
    'description["Is Finishing Charge"]',
    'let isCharging = onACPower && reportsCharging && !isFinishingCharge && belowFullCapacity && hasRemainingChargeTime',
    'lower.contains("finishing charge")',
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
    print('Prepared native power state with finishing-charge handling')
else:
    print('Native power callbacks and finishing-charge handling already prepared')
PY