import AppKit
import Darwin
import Foundation
import MagSafeCore

private let supportURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/MagSafe Dark/Schedule", isDirectory: true)
private let scheduleURL = supportURL.appendingPathComponent("schedule.json")
private let schedulerPath = "/usr/local/libexec/magsafe-scheduler"

private let modeItems: [(String, LEDMode)] = [
    ("Штатный режим", .system),
    ("Выключено", .off),
    ("Зелёный", .green),
    ("Оранжевый", .orange),
    ("Одиночная индикация", .flash),
    ("Медленное мигание", .blinkSlow),
    ("Быстрое мигание", .blinkFast),
    ("Мигание с выключением", .blinkOff)
]

private func defaultSchedule() throws -> LEDSchedule {
    LEDSchedule(enabled: false, fallback: .system, rules: [
        try ScheduleRule(days: Set(1...7), start: ScheduleTime("08:00"), end: ScheduleTime("23:00"), mode: .system),
        try ScheduleRule(days: Set(1...7), start: ScheduleTime("23:00"), end: ScheduleTime("08:00"), mode: .off)
    ])
}

private func loadSchedule() throws -> LEDSchedule {
    guard FileManager.default.fileExists(atPath: scheduleURL.path) else { return try defaultSchedule() }
    return try JSONDecoder().decode(LEDSchedule.self, from: Data(contentsOf: scheduleURL))
}

private func saveSchedule(_ schedule: LEDSchedule) throws {
    try schedule.validate()
    try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(schedule).write(to: scheduleURL, options: .atomic)
}

private func runScheduler(_ arguments: [String]) {
    guard FileManager.default.isExecutableFile(atPath: schedulerPath) else { return }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: schedulerPath)
    task.arguments = arguments
    try? task.run()
    task.waitUntilExit()
}

private func date(for time: ScheduleTime) -> Date {
    Calendar.current.date(from: DateComponents(hour: time.hour, minute: time.minute)) ?? Date()
}

private func scheduleTime(from date: Date) throws -> ScheduleTime {
    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
    return try ScheduleTime(hour: components.hour ?? 0, minute: components.minute ?? 0)
}

final class EditorController: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private var schedule: LEDSchedule
    private var selectedRuleIndex: Int?
    private var isChangingSelection = false

    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 760, height: 430),
        styleMask: [.titled, .closable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    private let enabled = NSButton(checkboxWithTitle: "Использовать расписание", target: nil, action: nil)
    private let fallback = NSPopUpButton()
    private let table = NSTableView()
    private let editorBox = NSBox()
    private var dayButtons: [NSButton] = []
    private let startPicker = NSDatePicker()
    private let endPicker = NSDatePicker()
    private let modePopup = NSPopUpButton()
    private let ruleEnabled = NSButton(checkboxWithTitle: "Интервал включён", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    override init() {
        schedule = (try? loadSchedule()) ?? (try! defaultSchedule())
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildUI()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !schedule.rules.isEmpty {
            selectRule(at: 0)
        } else {
            setEditorEnabled(false)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildUI() {
        window.title = "Расписание MagSafe Dark"
        let root = NSView(frame: window.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        window.contentView = root

        enabled.frame = NSRect(x: 20, y: 384, width: 220, height: 24)
        enabled.state = schedule.enabled ? .on : .off
        root.addSubview(enabled)

        fallback.frame = NSRect(x: 390, y: 379, width: 335, height: 30)
        fallback.addItems(withTitles: ["Вне расписания — штатный режим", "Вне расписания — выключено", "Вне расписания — постоянный режим"])
        fallback.selectItem(at: schedule.fallback == .system ? 0 : schedule.fallback == .off ? 1 : 2)
        root.addSubview(fallback)

        let scroll = NSScrollView(frame: NSRect(x: 20, y: 82, width: 275, height: 282))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        table.headerView = nil
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.delegate = self
        table.dataSource = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("summary"))
        column.width = 260
        table.addTableColumn(column)
        scroll.documentView = table
        root.addSubview(scroll)

        let add = NSButton(title: "+ Добавить", target: self, action: #selector(addRule))
        add.frame = NSRect(x: 20, y: 44, width: 105, height: 28)
        root.addSubview(add)
        let remove = NSButton(title: "Удалить", target: self, action: #selector(removeRule))
        remove.frame = NSRect(x: 135, y: 44, width: 95, height: 28)
        root.addSubview(remove)

        editorBox.titlePosition = .noTitle
        editorBox.frame = NSRect(x: 315, y: 82, width: 425, height: 282)
        root.addSubview(editorBox)
        buildRuleEditor(in: editorBox.contentView!)

        statusLabel.frame = NSRect(x: 20, y: 18, width: 470, height: 20)
        statusLabel.textColor = .systemRed
        root.addSubview(statusLabel)

        let cancel = NSButton(title: "Отмена", target: self, action: #selector(cancel))
        cancel.frame = NSRect(x: 550, y: 12, width: 90, height: 32)
        root.addSubview(cancel)
        let save = NSButton(title: "Сохранить", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        save.frame = NSRect(x: 650, y: 12, width: 90, height: 32)
        root.addSubview(save)
    }

    private func buildRuleEditor(in view: NSView) {
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

    private func configureTimePicker(_ picker: NSDatePicker, frame: NSRect, view: NSView) {
        picker.frame = frame
        picker.datePickerElements = [.hourMinute]
        picker.datePickerStyle = .textFieldAndStepper
        picker.target = self
        picker.action = #selector(updateSelectedRule)
        view.addSubview(picker)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { schedule.rules.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard schedule.rules.indices.contains(row) else { return nil }
        let rule = schedule.rules[row]
        let field = NSTextField(labelWithString: summary(for: rule))
        field.lineBreakMode = .byTruncatingTail
        field.textColor = rule.enabled ? .labelColor : .secondaryLabelColor
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isChangingSelection else { return }
        let newRow = table.selectedRow
        guard newRow >= 0, schedule.rules.indices.contains(newRow) else {
            if !schedule.rules.isEmpty { selectRule(at: min(selectedRuleIndex ?? 0, schedule.rules.count - 1)) }
            else { selectedRuleIndex = nil; setEditorEnabled(false) }
            return
        }

        let previousIndex = selectedRuleIndex
        if previousIndex != newRow {
            saveEditorIntoSelectedRule(showErrors: false, reloadTable: false)
        }
        loadRule(at: newRow)
    }

    private func selectRule(at index: Int) {
        guard schedule.rules.indices.contains(index) else { return }
        isChangingSelection = true
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        isChangingSelection = false
        loadRule(at: index)
    }

    private func summary(for rule: ScheduleRule) -> String {
        let days = compactDays(rule.days)
        let mode = modeItems.first(where: { $0.1 == rule.mode })?.0 ?? rule.mode.rawValue
        return "\(days)   \(rule.start.stringValue)–\(rule.end.stringValue)   \(mode)"
    }

    private func compactDays(_ days: Set<Int>) -> String {
        if days == Set(1...7) { return "Каждый день" }
        if days == Set(1...5) { return "Пн–Пт" }
        if days == Set([6, 7]) { return "Сб–Вс" }
        let names = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
        return days.sorted().map { names[$0 - 1] }.joined(separator: ", ")
    }

    private func loadRule(at index: Int) {
        guard schedule.rules.indices.contains(index) else { return }
        selectedRuleIndex = index
        let rule = schedule.rules[index]
        setEditorEnabled(true)
        ruleEnabled.state = rule.enabled ? .on : .off
        for button in dayButtons { button.state = rule.days.contains(button.tag) ? .on : .off }
        startPicker.dateValue = date(for: rule.start)
        endPicker.dateValue = date(for: rule.end)
        modePopup.selectItem(at: modeItems.firstIndex(where: { $0.1 == rule.mode }) ?? 0)
        statusLabel.stringValue = ""
    }

    private func setEditorEnabled(_ value: Bool) {
        ruleEnabled.isEnabled = value
        dayButtons.forEach { $0.isEnabled = value }
        startPicker.isEnabled = value
        endPicker.isEnabled = value
        modePopup.isEnabled = value
    }

    @objc private func updateSelectedRule() {
        saveEditorIntoSelectedRule(showErrors: true)
    }

    private func saveEditorIntoSelectedRule(showErrors: Bool, reloadTable: Bool = true) {
        guard let index = selectedRuleIndex, schedule.rules.indices.contains(index) else { return }
        do {
            let days = Set(dayButtons.filter { $0.state == .on }.map(\.tag))
            guard !days.isEmpty else { throw ScheduleValidationError.invalidWeekday }
            schedule.rules[index].enabled = ruleEnabled.state == .on
            schedule.rules[index].days = days
            schedule.rules[index].start = try scheduleTime(from: startPicker.dateValue)
            schedule.rules[index].end = try scheduleTime(from: endPicker.dateValue)
            schedule.rules[index].mode = modeItems[modePopup.indexOfSelectedItem].1
            statusLabel.stringValue = ""
            if reloadTable {
                isChangingSelection = true
                table.reloadData()
                isChangingSelection = false
            }
        } catch {
            if showErrors {
                statusLabel.stringValue = "Выберите хотя бы один день и корректное время."
                NSSound.beep()
            }
        }
    }

    @objc private func addRule() {
        saveEditorIntoSelectedRule(showErrors: false)
        let rule = try! ScheduleRule(days: Set(1...7), start: ScheduleTime("09:00"), end: ScheduleTime("18:00"), mode: .system)
        schedule.rules.append(rule)
        table.reloadData()
        selectRule(at: schedule.rules.count - 1)
    }

    @objc private func removeRule() {
        let row = table.selectedRow
        guard row >= 0, schedule.rules.indices.contains(row) else { return }
        schedule.rules.remove(at: row)
        table.reloadData()
        if schedule.rules.isEmpty {
            selectedRuleIndex = nil
            setEditorEnabled(false)
        } else {
            selectRule(at: min(row, schedule.rules.count - 1))
        }
    }

    @objc private func save() {
        saveEditorIntoSelectedRule(showErrors: true)
        let wasEnabled = schedule.enabled
        schedule.enabled = enabled.state == .on
        schedule.fallback = fallback.indexOfSelectedItem == 0 ? .system : fallback.indexOfSelectedItem == 1 ? .off : .persistent
        do {
            try saveSchedule(schedule)
            if !wasEnabled && schedule.enabled {
                runScheduler(["clear-manual"])
            } else {
                runScheduler(["apply"])
            }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["kickstart", "-k", "gui/\(getuid())/su.xyz.MagSafeDark.scheduler"]
            try? task.run()
            window.close()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Не удалось сохранить расписание"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func cancel() { window.close() }
}

let app = NSApplication.shared
let controller = EditorController()
app.delegate = controller
app.setActivationPolicy(.regular)
app.run()
