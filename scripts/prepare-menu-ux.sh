#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

python3 <<'PY'
from pathlib import Path
import re

main = Path("Sources/MagSafeDark/main.swift")
text = main.read_text()
original = text

# Make the two primary LED actions permanently visible and expose manual-control reset.
old_primary = '''        let toggle = cachedMode == 1
            ? item(text("Вернуть штатный режим", "Restore system mode"), #selector(systemMode), key: "0")
            : item(text("Выключить лампочку", "Turn LED off"), #selector(turnOff), key: "0")
        toggle.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(toggle)
'''
new_primary = '''        let system = item(text("Вернуть штатный режим", "Restore system mode"), #selector(systemMode), key: "0")
        system.keyEquivalentModifierMask = [.command, .shift]
        system.state = cachedMode == 0 && !cachedTemporaryActive ? .on : .off
        menu.addItem(system)

        let off = item(text("Выключить индикатор", "Turn indicator off"), #selector(turnOff))
        off.state = cachedMode == 1 ? .on : .off
        menu.addItem(off)

        let cancelManual = item(text("Отменить ручное управление", "Cancel manual control"), #selector(cancelManualControl))
        cancelManual.isEnabled = cachedTemporaryActive
        menu.addItem(cancelManual)
'''
if old_primary in text:
    text = text.replace(old_primary, new_primary, 1)

# Show the active mode in color/effect submenus.
old_mode_item = '''        let result = item(title, #selector(selectMode(_:)), key: key)
        result.representedObject = mode
        if !key.isEmpty { result.keyEquivalentModifierMask = [.command, .shift] }
        return result
'''
new_mode_item = '''        let result = item(title, #selector(selectMode(_:)), key: key)
        result.representedObject = mode
        result.state = expectedValue(for: mode) == cachedMode ? .on : .off
        if !key.isEmpty { result.keyEquivalentModifierMask = [.command, .shift] }
        return result
'''
if old_mode_item in text:
    text = text.replace(old_mode_item, new_mode_item, 1)

# Clarify who currently controls the indicator.
old_title = '''    private func currentModeTitle(_ mode: UInt8?) -> String {
        text("Текущий режим: \\(modeName(mode))", "Current mode: \\(modeName(mode))")
    }
'''
new_title = '''    private func currentModeTitle(_ mode: UInt8?) -> String {
        let base = text("Текущий режим: \\(modeName(mode))", "Current mode: \\(modeName(mode))")
        if cachedTemporaryActive {
            if let end = cachedTimerEnd {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                return base + text(" — вручную до \\(formatter.string(from: end))", " — manual until \\(formatter.string(from: end))")
            }
            return base + text(" — ручное управление", " — manual control")
        }
        return base + (scheduleEnabled ? text(" — по расписанию", " — scheduled") : "")
    }
'''
if old_title in text:
    text = text.replace(old_title, new_title, 1)

# Add a quick schedule switch above the settings submenu.
schedule_anchor = '        menu.addItem(submenu(text("Настройки", "Settings"), settings))\n'
if '#selector(toggleSchedule)' not in text and schedule_anchor in text:
    schedule_item = '''        let scheduleToggle = item(text("Расписание включено", "Schedule enabled"), #selector(toggleSchedule))
        scheduleToggle.state = scheduleEnabled ? .on : .off
        menu.addItem(scheduleToggle)
'''
    text = text.replace(schedule_anchor, schedule_item + schedule_anchor, 1)

# Organize settings and restore the missing power-connection option with a clear name.
text = text.replace(
'''        settings.addItem(submenu(text("Вид значка", "Icon appearance"), appearance))

        let batteryPercentage''',
'''        settings.addItem(submenu(text("Вид значка", "Icon appearance"), appearance))
        settings.addItem(.separator())

        let batteryPercentage''', 1)

charging_anchor = '''        let chargeCompletion = item(text("Показывать время окончания зарядки", "Show charge completion time"), #selector(toggleChargeCompletion))'''
if '#selector(toggleChargingState)' not in text and charging_anchor in text:
    charging = '''        let chargingState = item(text("Показывать подключение к питанию", "Show power connection"), #selector(toggleChargingState))
        chargingState.state = defaults.bool(forKey: showChargingStateKey) ? .on : .off
        settings.addItem(chargingState)

'''
    text = text.replace(charging_anchor, charging + charging_anchor, 1)
else:
    text = text.replace('text("Показывать состояние зарядки", "Show charging state")', 'text("Показывать подключение к питанию", "Show power connection")')

text = text.replace(
'''        settings.addItem(submenu(text("Остаток таймера", "Timer countdown"), timerDisplay))

        settings.addItem(codexSettingsItem())''',
'''        settings.addItem(submenu(text("Остаток таймера", "Timer countdown"), timerDisplay))
        settings.addItem(.separator())

        settings.addItem(codexSettingsItem())''', 1)

# Timer menu wording: separate temporary mode choices from cancellation.
text = text.replace('menu.addItem(submenu(text("Таймер", "Timer"), timers))', 'menu.addItem(submenu(text("Временный режим", "Temporary mode"), timers))')
text = text.replace('text("Другой таймер…", "Custom timer…")', 'text("Другой временный режим…", "Custom temporary mode…")')

# Scheduler helpers and actions.
helper_anchor = '    private var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }\n'
if 'private var scheduleEnabled: Bool' not in text and helper_anchor in text:
    helpers = r'''    private var scheduleURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MagSafe Dark/Schedule/schedule.json")
    }

    private var scheduleEnabled: Bool {
        guard let data = try? Data(contentsOf: scheduleURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["enabled"] as? Bool ?? false
    }

    private func setScheduleEnabled(_ enabled: Bool) throws {
        var object: [String: Any]
        if let data = try? Data(contentsOf: scheduleURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object = existing
        } else {
            object = ["enabled": false, "fallback": "system", "rules": []]
        }
        object["enabled"] = enabled
        try FileManager.default.createDirectory(at: scheduleURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: scheduleURL, options: .atomic)
    }

'''
    text = text.replace(helper_anchor, helpers + helper_anchor, 1)

action_anchor = '    @objc private func turnOff() { executeState("off") }\n'
if '@objc private func cancelManualControl()' not in text and action_anchor in text:
    actions = '''    @objc private func cancelManualControl() {
        commandQueue.async { [weak self] in
            guard let self else { return }
            let result = self.run(self.automationCLI, ["schedule", "clear-manual"])
            DispatchQueue.main.async {
                if result.status != 0 {
                    self.alert(self.text("Не удалось отменить ручное управление", "Could not cancel manual control"), result.output)
                }
                self.requestRefresh(force: true)
                self.rebuildMenu()
            }
        }
    }

    @objc private func toggleSchedule() {
        do {
            let enable = !scheduleEnabled
            try setScheduleEnabled(enable)
            commandQueue.async { [weak self] in
                guard let self else { return }
                _ = self.run(self.automationCLI, ["schedule", enable ? "clear-manual" : "apply"])
                DispatchQueue.main.async {
                    self.requestRefresh(force: true)
                    self.rebuildMenu()
                }
            }
        } catch {
            alert(text("Не удалось изменить расписание", "Could not change schedule"), error.localizedDescription)
        }
    }

'''
    text = text.replace(action_anchor, actions + action_anchor, 1)

# Restore missing settings action when older source revisions removed it.
toggle_anchor = '    @objc private func toggleChargeCompletion() {\n'
if '@objc private func toggleChargingState()' not in text and toggle_anchor in text:
    method = '''    @objc private func toggleChargingState() {
        defaults.set(!defaults.bool(forKey: showChargingStateKey), forKey: showChargingStateKey)
        updateStatusIcon(mode: cachedMode, remaining: cachedTimerRemaining)
        rebuildMenu()
        requestRefresh(force: true)
    }

'''
    text = text.replace(toggle_anchor, method + toggle_anchor, 1)

if text != original:
    main.write_text(text)

# Improve schedule editor wording and mark the rule active at the current moment.
editor = Path("Sources/ScheduleEditor/main.swift")
etext = editor.read_text()
eoriginal = etext
etext = etext.replace(
    '"Вне расписания — постоянный режим"',
    '"Вне расписания — сохранять последний режим"'
)

old_summary = '''    private func summary(for rule: ScheduleRule) -> String {
        let days = compactDays(rule.days)
        let mode = modeItems.first(where: { $0.1 == rule.mode })?.0 ?? rule.mode.rawValue
        return "\\(days)   \\(rule.start.stringValue)–\\(rule.end.stringValue)   \\(mode)"
    }
'''
new_summary = '''    private func summary(for rule: ScheduleRule) -> String {
        let days = compactDays(rule.days)
        let mode = modeItems.first(where: { $0.1 == rule.mode })?.0 ?? rule.mode.rawValue
        let active = rule.enabled && ruleIsActiveNow(rule) ? "●  " : ""
        return "\\(active)\\(days)   \\(rule.start.stringValue)–\\(rule.end.stringValue)   \\(mode)"
    }

    private func ruleIsActiveNow(_ rule: ScheduleRule) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let normalizedDay = weekday == 1 ? 7 : weekday - 1
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let start = rule.start.hour * 60 + rule.start.minute
        let end = rule.end.hour * 60 + rule.end.minute
        if start == end { return rule.days.contains(normalizedDay) }
        if start < end { return rule.days.contains(normalizedDay) && minute >= start && minute < end }
        if minute >= start { return rule.days.contains(normalizedDay) }
        let previousDay = normalizedDay == 1 ? 7 : normalizedDay - 1
        return minute < end && rule.days.contains(previousDay)
    }
'''
if old_summary in etext:
    etext = etext.replace(old_summary, new_summary, 1)

if etext != eoriginal:
    editor.write_text(etext)

print("Prepared clearer menu actions, schedule controls and active-rule feedback")
PY
