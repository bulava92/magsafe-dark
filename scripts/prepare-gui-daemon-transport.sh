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

text = text.replace(
    'private let helper = "/usr/local/libexec/magsafe-led-helper"',
    'private let helper = "/usr/local/libexec/magsafe-led-client"'
)
text = text.replace(
    'let modeResult = run("/usr/bin/sudo", ["-n", helper, "status"])',
    'let modeResult = run(helper, ["status"])'
)

menu_anchor = 'menu.addItem(item(text("Диагностика…", "Diagnostics…"), #selector(showDiagnostics)))'
menu_line = 'menu.addItem(item(text("Настроить расписание…", "Configure schedule…"), #selector(openScheduleEditor)))\n        '
if '#selector(openScheduleEditor)' not in text:
    if menu_anchor not in text:
        raise SystemExit('Could not find diagnostics menu anchor')
    text = text.replace(menu_anchor, menu_line + menu_anchor, 1)

method_anchor = '    @objc private func showDiagnostics() {'
method = '''    @objc private func openScheduleEditor() {
        let editor = "/usr/local/libexec/magsafe-schedule-editor"
        do {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: editor)
            try task.run()
        } catch {
            alert(text("Не удалось открыть расписание", "Could not open schedule editor"), error.localizedDescription)
        }
    }

'''
if 'private func openScheduleEditor()' not in text:
    if method_anchor not in text:
        raise SystemExit('Could not find diagnostics method anchor')
    text = text.replace(method_anchor, method + method_anchor, 1)

# Battery percentage, charging state and estimated charge completion.
if 'let batteryPercent: Int?' not in text:
    text = text.replace(
        '        let timerEnd: Date?\n    }',
        '        let timerEnd: Date?\n        let batteryPercent: Int?\n        let onACPower: Bool?\n        let isCharging: Bool?\n        let chargeCompletion: Date?\n    }',
        1,
    )
else:
    if 'let onACPower: Bool?' not in text:
        text = text.replace('        let batteryPercent: Int?\n', '        let batteryPercent: Int?\n        let onACPower: Bool?\n', 1)
    if 'let isCharging: Bool?' not in text:
        text = text.replace('        let onACPower: Bool?\n', '        let onACPower: Bool?\n        let isCharging: Bool?\n        let chargeCompletion: Date?\n', 1)

if 'private var cachedBatteryPercent' not in text:
    text = text.replace(
        '    private var cachedTemporaryActive = false\n',
        '    private var cachedTemporaryActive = false\n    private var cachedBatteryPercent: Int?\n    private var cachedOnACPower: Bool?\n    private var cachedIsCharging: Bool?\n    private var cachedChargeCompletion: Date?\n',
        1,
    )
else:
    if 'private var cachedOnACPower' not in text:
        text = text.replace('    private var cachedBatteryPercent: Int?\n', '    private var cachedBatteryPercent: Int?\n    private var cachedOnACPower: Bool?\n', 1)
    if 'private var cachedIsCharging' not in text:
        text = text.replace('    private var cachedOnACPower: Bool?\n', '    private var cachedOnACPower: Bool?\n    private var cachedIsCharging: Bool?\n    private var cachedChargeCompletion: Date?\n', 1)

if 'showBatteryPercentageInStatusBar' not in text:
    text = text.replace(
        '    private let showTimerInMenuKey = "showTimerInMenu"\n',
        '    private let showTimerInMenuKey = "showTimerInMenu"\n    private let showBatteryPercentageKey = "showBatteryPercentageInStatusBar"\n    private let showChargingStateKey = "showChargingStateInStatusBar"\n    private let showChargeCompletionKey = "showChargeCompletionInStatusBar"\n',
        1,
    )
    text = text.replace(
        '            showTimerInMenuKey: false\n',
        '            showTimerInMenuKey: false,\n            showBatteryPercentageKey: false,\n            showChargingStateKey: false,\n            showChargeCompletionKey: false\n',
        1,
    )
else:
    text = text.replace('    private let showPowerSourceKey = "showPowerSourceInStatusBar"\n', '')
    if 'showChargingStateInStatusBar' not in text:
        text = text.replace(
            '    private let showBatteryPercentageKey = "showBatteryPercentageInStatusBar"\n',
            '    private let showBatteryPercentageKey = "showBatteryPercentageInStatusBar"\n    private let showChargingStateKey = "showChargingStateInStatusBar"\n    private let showChargeCompletionKey = "showChargeCompletionInStatusBar"\n',
            1,
        )
    text = text.replace('            showPowerSourceKey: false\n', '            showChargingStateKey: false,\n            showChargeCompletionKey: false\n')
    text = text.replace('            showPowerSourceKey: false,\n', '            showChargingStateKey: false,\n            showChargeCompletionKey: false,\n')

# Replace the battery/power settings block with three independent compact display settings.
settings_pattern = re.compile(
    r'        let batteryPercentage = item\(text\("Показывать процент заряда".*?settings\.addItem\(powerSource\)\n',
    re.S,
)
settings_block = '''        let batteryPercentage = item(text("Показывать процент заряда", "Show battery percentage"), #selector(toggleBatteryPercentage))
        batteryPercentage.state = defaults.bool(forKey: showBatteryPercentageKey) ? .on : .off
        settings.addItem(batteryPercentage)

        let chargingState = item(text("Показывать состояние зарядки", "Show charging state"), #selector(toggleChargingState))
        chargingState.state = defaults.bool(forKey: showChargingStateKey) ? .on : .off
        settings.addItem(chargingState)

        let chargeCompletion = item(text("Показывать время окончания зарядки", "Show charge completion time"), #selector(toggleChargeCompletion))
        chargeCompletion.state = defaults.bool(forKey: showChargeCompletionKey) ? .on : .off
        settings.addItem(chargeCompletion)
'''
text, replaced = settings_pattern.subn(settings_block, text, count=1)
if replaced == 0 and '#selector(toggleBatteryPercentage)' not in text:
    anchor = '        settings.addItem(submenu(text("Вид значка", "Icon appearance"), appearance))\n'
    if anchor not in text:
        raise SystemExit('Could not find icon appearance settings anchor')
    text = text.replace(anchor, anchor + '\n' + settings_block, 1)

# Remove old battery readers and install one structured reader.
text = re.sub(r'    private func readBatteryPercentage\(\) -> Int\? \{.*?\n    \}\n\n', '', text, count=1, flags=re.S)
text = re.sub(r'    private func readBatteryStatus\(\) -> \(percentage: Int\?, onACPower: Bool\?\) \{.*?\n    \}\n\n', '', text, count=1, flags=re.S)

if 'private func readBatteryStatus() -> (percentage: Int?, onACPower: Bool?, isCharging: Bool?, chargeCompletion: Date?)' not in text:
    read_anchor = '    private func readSnapshot() -> Snapshot {'
    read_method = '''    private func readBatteryStatus() -> (percentage: Int?, onACPower: Bool?, isCharging: Bool?, chargeCompletion: Date?) {
        let result = run("/usr/bin/pmset", ["-g", "batt"])
        guard result.status == 0 else { return (nil, nil, nil, nil) }

        var percentage: Int?
        if let expression = try? NSRegularExpression(pattern: #"(\\d{1,3})%"#),
           let match = expression.firstMatch(in: result.output, range: NSRange(result.output.startIndex..., in: result.output)),
           let range = Range(match.range(at: 1), in: result.output),
           let value = Int(result.output[range]),
           (0...100).contains(value) {
            percentage = value
        }

        let lower = result.output.lowercased()
        let onACPower: Bool?
        if result.output.contains("AC Power") { onACPower = true }
        else if result.output.contains("Battery Power") { onACPower = false }
        else { onACPower = nil }

        let isCharging: Bool?
        if lower.contains("not charging") || lower.contains("charged") { isCharging = false }
        else if lower.contains("charging") || lower.contains("finishing charge") { isCharging = true }
        else if onACPower == false { isCharging = false }
        else { isCharging = nil }

        var chargeCompletion: Date?
        if isCharging == true,
           let expression = try? NSRegularExpression(pattern: #"(\\d+):(\\d{2}) remaining"#),
           let match = expression.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let hourRange = Range(match.range(at: 1), in: lower),
           let minuteRange = Range(match.range(at: 2), in: lower),
           let hours = Int(lower[hourRange]),
           let minutes = Int(lower[minuteRange]) {
            chargeCompletion = Date().addingTimeInterval(TimeInterval(hours * 3600 + minutes * 60))
        }

        return (percentage, onACPower, isCharging, chargeCompletion)
    }

'''
    if read_anchor not in text:
        raise SystemExit('Could not find snapshot reader anchor')
    text = text.replace(read_anchor, read_method + read_anchor, 1)

text = text.replace('        let batteryPercent = readBatteryPercentage()\n', '        let batteryStatus = readBatteryStatus()\n')
if 'let batteryStatus = readBatteryStatus()' not in text:
    text = text.replace('        let timerEndResult = run(automationCLI, ["timer-end"])\n', '        let timerEndResult = run(automationCLI, ["timer-end"])\n        let batteryStatus = readBatteryStatus()\n', 1)

for old in [
    'return Snapshot(mode: mode, remaining: remaining, temporary: temporaryResult.status == 0, timerEnd: end, batteryPercent: batteryStatus.percentage, onACPower: batteryStatus.onACPower)',
    'return Snapshot(mode: mode, remaining: remaining, temporary: temporaryResult.status == 0, timerEnd: end, batteryPercent: batteryPercent)',
    'return Snapshot(mode: mode, remaining: remaining, temporary: temporaryResult.status == 0, timerEnd: end)',
]:
    text = text.replace(old, 'return Snapshot(mode: mode, remaining: remaining, temporary: temporaryResult.status == 0, timerEnd: end, batteryPercent: batteryStatus.percentage, onACPower: batteryStatus.onACPower, isCharging: batteryStatus.isCharging, chargeCompletion: batteryStatus.chargeCompletion)')

text = re.sub(
    r'Snapshot\(mode: expected, remaining: snapshot\.remaining, temporary: snapshot\.temporary, timerEnd: snapshot\.timerEnd(?:, batteryPercent: snapshot\.batteryPercent(?:, onACPower: snapshot\.onACPower)?)?\)',
    'Snapshot(mode: expected, remaining: snapshot.remaining, temporary: snapshot.temporary, timerEnd: snapshot.timerEnd, batteryPercent: snapshot.batteryPercent, onACPower: snapshot.onACPower, isCharging: snapshot.isCharging, chargeCompletion: snapshot.chargeCompletion)',
    text,
)

if 'self.cachedBatteryPercent = snapshot.batteryPercent' not in text:
    text = text.replace('                self.cachedTimerEnd = snapshot.timerEnd\n', '                self.cachedTimerEnd = snapshot.timerEnd\n                self.cachedBatteryPercent = snapshot.batteryPercent\n                self.cachedOnACPower = snapshot.onACPower\n                self.cachedIsCharging = snapshot.isCharging\n                self.cachedChargeCompletion = snapshot.chargeCompletion\n', 1)
else:
    if 'self.cachedOnACPower = snapshot.onACPower' not in text:
        text = text.replace('                self.cachedBatteryPercent = snapshot.batteryPercent\n', '                self.cachedBatteryPercent = snapshot.batteryPercent\n                self.cachedOnACPower = snapshot.onACPower\n', 1)
    if 'self.cachedIsCharging = snapshot.isCharging' not in text:
        text = text.replace('                self.cachedOnACPower = snapshot.onACPower\n', '                self.cachedOnACPower = snapshot.onACPower\n                self.cachedIsCharging = snapshot.isCharging\n                self.cachedChargeCompletion = snapshot.chargeCompletion\n', 1)

# Compact text: ⚡ means actively charging, AC means connected but not charging. Nothing is shown on battery power.
text = re.sub(
    r'        var statusParts: \[String\] = \[\].*?statusItem\.button\?\.title = .*?\n',
    '''        var statusParts: [String] = []
        if defaults.bool(forKey: showBatteryPercentageKey), let battery = cachedBatteryPercent {
            statusParts.append("\\(battery)%")
        }
        if defaults.bool(forKey: showChargingStateKey), cachedOnACPower == true {
            statusParts.append(cachedIsCharging == true ? "⚡" : "AC")
        }
        if defaults.bool(forKey: showChargeCompletionKey), cachedIsCharging == true, let completion = cachedChargeCompletion {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            statusParts.append(formatter.string(from: completion))
        }
        if defaults.bool(forKey: showTimerInStatusBarKey), let remaining {
            statusParts.append(formatDuration(remaining))
        }
        statusItem.button?.title = statusParts.isEmpty ? "" : " " + statusParts.joined(separator: " ")
''',
    text,
    count=1,
    flags=re.S,
)
old_title = '        statusItem.button?.title = defaults.bool(forKey: showTimerInStatusBarKey) && remaining != nil ? "  \\(formatDuration(remaining!))" : ""'
if old_title in text:
    text = text.replace(old_title, '''        var statusParts: [String] = []
        if defaults.bool(forKey: showBatteryPercentageKey), let battery = cachedBatteryPercent {
            statusParts.append("\\(battery)%")
        }
        if defaults.bool(forKey: showChargingStateKey), cachedOnACPower == true {
            statusParts.append(cachedIsCharging == true ? "⚡" : "AC")
        }
        if defaults.bool(forKey: showChargeCompletionKey), cachedIsCharging == true, let completion = cachedChargeCompletion {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            statusParts.append(formatter.string(from: completion))
        }
        if defaults.bool(forKey: showTimerInStatusBarKey), let remaining {
            statusParts.append(formatDuration(remaining))
        }
        statusItem.button?.title = statusParts.isEmpty ? "" : " " + statusParts.joined(separator: " ")''', 1)

# Remove old source toggle method and install the two new toggles.
text = re.sub(r'    @objc private func togglePowerSource\(\) \{.*?\n    \}\n\n', '', text, count=1, flags=re.S)
if '@objc private func toggleBatteryPercentage()' not in text:
    anchor = '    @objc private func toggleTimerInStatusBar() {'
    method = '''    @objc private func toggleBatteryPercentage() {
        defaults.set(!defaults.bool(forKey: showBatteryPercentageKey), forKey: showBatteryPercentageKey)
        updateStatusIcon(mode: cachedMode, remaining: cachedTimerRemaining)
        rebuildMenu()
        requestRefresh(force: true)
    }

'''
    text = text.replace(anchor, method + anchor, 1)

if '@objc private func toggleChargingState()' not in text:
    anchor = '    @objc private func toggleTimerInStatusBar() {'
    methods = '''    @objc private func toggleChargingState() {
        defaults.set(!defaults.bool(forKey: showChargingStateKey), forKey: showChargingStateKey)
        updateStatusIcon(mode: cachedMode, remaining: cachedTimerRemaining)
        rebuildMenu()
        requestRefresh(force: true)
    }

    @objc private func toggleChargeCompletion() {
        defaults.set(!defaults.bool(forKey: showChargeCompletionKey), forKey: showChargeCompletionKey)
        updateStatusIcon(mode: cachedMode, remaining: cachedTimerRemaining)
        rebuildMenu()
        requestRefresh(force: true)
    }

'''
    text = text.replace(anchor, methods + anchor, 1)

if '/usr/bin/sudo' in text or 'magsafe-led-helper' in text:
    raise SystemExit('GUI still contains legacy sudo/helper transport')
for marker in ['showChargingStateInStatusBar', 'showChargeCompletionInStatusBar', 'isCharging', 'chargeCompletion', '#selector(toggleChargingState)', '#selector(toggleChargeCompletion)']:
    if marker not in text:
        raise SystemExit(f'Missing prepared GUI marker: {marker}')
if '"BAT"' in text:
    raise SystemExit('Legacy BAT label remains in GUI source')

if text != original:
    path.write_text(text)
    print('Prepared GUI transport, schedule editor and compact charging status')
else:
    print('GUI transport, schedule editor and compact charging status already prepared')
PY