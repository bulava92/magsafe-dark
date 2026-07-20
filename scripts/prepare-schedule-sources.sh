#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
python3 <<'PY'
from pathlib import Path
import re

scheduler = Path('Sources/MagSafeScheduler/main.swift')
text = scheduler.read_text()
text = text.replace(
    'if status.deferredByTemporaryState && !force { return 0 }',
    'if status.deferredByTemporaryState { return 0 }'
)
text = text.replace(
    'if let boundary = status.nextBoundary {\n            delay = max(1, min(boundary.timeIntervalSinceNow + 0.5, 3600))',
    'if status.deferredByTemporaryState {\n            delay = 2\n        } else if let boundary = status.nextBoundary {\n            delay = max(1, min(boundary.timeIntervalSinceNow + 0.5, 3600))'
)
scheduler.write_text(text)

editor = Path('Sources/ScheduleEditor/main.swift')
text = editor.read_text()
if 'import Darwin' not in text:
    text = text.replace('import AppKit\n', 'import AppKit\nimport Darwin\n', 1)
text = text.replace('runScheduler(["apply", "--force"])', 'runScheduler(["apply"])')
text = text.replace(
    'table.headerView = nil\n        table.delegate = self',
    'table.headerView = nil\n        table.allowsEmptySelection = false\n        table.allowsMultipleSelection = false\n        table.delegate = self'
)
text = text.replace(
    'guard newRow >= 0, schedule.rules.indices.contains(newRow) else {\n            selectedRuleIndex = nil\n            setEditorEnabled(false)\n            return\n        }',
    'guard newRow >= 0, schedule.rules.indices.contains(newRow) else {\n            if !schedule.rules.isEmpty { selectRule(at: min(selectedRuleIndex ?? 0, schedule.rules.count - 1)) }\n            else { selectedRuleIndex = nil; setEditorEnabled(false) }\n            return\n        }'
)

text = re.sub(
    r'\n        let fallbackLabel = NSTextField\(labelWithString: "Вне интервалов:"\).*?root\.addSubview\(fallbackLabel\)\n',
    '\n', text, count=1, flags=re.S
)
text = text.replace('fallback.frame = NSRect(x: 505, y: 380, width: 220, height: 28)', 'fallback.frame = NSRect(x: 390, y: 379, width: 335, height: 30)')
text = text.replace('fallback.frame = NSRect(x: 510, y: 379, width: 215, height: 30)', 'fallback.frame = NSRect(x: 390, y: 379, width: 335, height: 30)')
text = text.replace(
    'fallback.addItems(withTitles: ["Штатный режим", "Выключено", "Постоянный режим"])',
    'fallback.addItems(withTitles: ["Вне расписания — штатный режим", "Вне расписания — выключено", "Вне расписания — постоянный режим"])'
)
text = text.replace(
    'editorBox.title = "Интервал"\n        editorBox.frame = NSRect(x: 315, y: 82, width: 425, height: 282)',
    'editorBox.titlePosition = .noTitle\n        editorBox.frame = NSRect(x: 315, y: 82, width: 425, height: 282)'
)

new_editor = r'''    private func buildRuleEditor(in view: NSView) {
        ruleEnabled.frame = NSRect(x: 24, y: 230, width: 220, height: 24)
        ruleEnabled.target = self
        ruleEnabled.action = #selector(updateSelectedRule)
        view.addSubview(ruleEnabled)

        let daysLabel = NSTextField(labelWithString: "Дни недели")
        daysLabel.frame = NSRect(x: 24, y: 193, width: 370, height: 20)
        daysLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        view.addSubview(daysLabel)

        let dayTitles = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
        for (index, title) in dayTitles.enumerated() {
            let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(updateSelectedRule))
            button.frame = NSRect(x: 24 + index * 54, y: 163, width: 52, height: 24)
            button.tag = index + 1
            dayButtons.append(button)
            view.addSubview(button)
        }

        let startLabel = NSTextField(labelWithString: "Начало")
        startLabel.frame = NSRect(x: 24, y: 125, width: 170, height: 20)
        startLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        view.addSubview(startLabel)
        configureTimePicker(startPicker, frame: NSRect(x: 24, y: 92, width: 170, height: 28), view: view)

        let endLabel = NSTextField(labelWithString: "Конец")
        endLabel.frame = NSRect(x: 218, y: 125, width: 176, height: 20)
        endLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        view.addSubview(endLabel)
        configureTimePicker(endPicker, frame: NSRect(x: 218, y: 92, width: 176, height: 28), view: view)

        let modeLabel = NSTextField(labelWithString: "Режим индикатора")
        modeLabel.frame = NSRect(x: 24, y: 57, width: 370, height: 20)
        modeLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        view.addSubview(modeLabel)

        modePopup.frame = NSRect(x: 24, y: 23, width: 370, height: 30)
        modePopup.addItems(withTitles: modeItems.map(\.0))
        modePopup.target = self
        modePopup.action = #selector(updateSelectedRule)
        view.addSubview(modePopup)
    }

'''
pattern = re.compile(r'    private func buildRuleEditor\(in view: NSView\) \{.*?\n    \}\n\n(?=    private func configureTimePicker)', re.S)
text, count = pattern.subn(lambda _: new_editor, text, count=1)
if count != 1:
    raise SystemExit('Could not replace schedule editor layout')

# Enabling the schedule is an explicit transfer of control to the schedule.
# Clear any old manual-until-boundary override and apply the current rule immediately.
text = text.replace(
    'saveEditorIntoSelectedRule(showErrors: true)\n        schedule.enabled = enabled.state == .on',
    'saveEditorIntoSelectedRule(showErrors: true)\n        let wasEnabled = schedule.enabled\n        schedule.enabled = enabled.state == .on'
)
text = text.replace(
    'try saveSchedule(schedule)\n            runScheduler(["apply"])',
    'try saveSchedule(schedule)\n            if !wasEnabled && schedule.enabled {\n                runScheduler(["clear-manual"])\n            } else {\n                runScheduler(["apply"])\n            }'
)

editor.write_text(text)
print('Prepared schedule editor layout v3 and immediate schedule activation')
PY