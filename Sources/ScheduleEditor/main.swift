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
        contentRect: NSRect(x: 0, y: 0, width: 860, height: 540),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    private let enabled = NSButton(checkboxWithTitle: "Использовать расписание", target: nil, action: nil)
    private let fallback = NSPopUpButton()
    private let table = NSTableView()
    private var dayButtons: [NSButton] = []
    private let startPicker = NSDatePicker()
    private let endPicker = NSDatePicker()
    private let modePopup = NSPopUpButton()
    private let ruleEnabled = NSButton(checkboxWithTitle: "Интервал включён", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let removeButton = NSButton(title: "Удалить", target: nil, action: nil)

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
        window.minSize = NSSize(width: 760, height: 500)
        window.setFrameAutosaveName("MagSafeDarkScheduleEditorWindow")

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let title = NSTextField(labelWithString: "Расписание индикатора")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Настройте режим MagSafe для выбранных дней и интервалов времени.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 2

        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 4

        enabled.state = schedule.enabled ? .on : .off

        fallback.addItems(withTitles: [
            "Штатный режим",
            "Выключено",
            "Постоянный режим"
        ])
        fallback.selectItem(at: schedule.fallback == .system ? 0 : schedule.fallback == .off ? 1 : 2)

        let fallbackLabel = NSTextField(labelWithString: "Вне расписания:")
        fallbackLabel.textColor = .secondaryLabelColor

        let fallbackRow = NSStackView(views: [fallbackLabel, fallback])
        fallbackRow.orientation = .horizontal
        fallbackRow.alignment = .centerY
        fallbackRow.spacing = 8

        let settingsRow = NSStackView(views: [enabled, NSView(), fallbackRow])
        settingsRow.orientation = .horizontal
        settingsRow.alignment = .centerY
        settingsRow.spacing = 12

        let header = NSStackView(views: [heading, settingsRow])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 14

        table.headerView = nil
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.rowHeight = 52
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.selectionHighlightStyle = .regular
        table.delegate = self
        table.dataSource = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("summary"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.documentView = table

        let listTitle = NSTextField(labelWithString: "Интервалы")
        listTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        let addButton = NSButton(title: "Добавить", target: self, action: #selector(addRule))
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.imagePosition = .imageLeading

        removeButton.target = self
        removeButton.action = #selector(removeRule)
        removeButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        removeButton.imagePosition = .imageLeading

        let listButtons = NSStackView(views: [addButton, removeButton, NSView()])
        listButtons.orientation = .horizontal
        listButtons.alignment = .centerY
        listButtons.spacing = 8

        let listPanel = NSStackView(views: [listTitle, scroll, listButtons])
        listPanel.orientation = .vertical
        listPanel.alignment = .leading
        listPanel.spacing = 10
        listPanel.translatesAutoresizingMaskIntoConstraints = false

        scroll.widthAnchor.constraint(equalTo: listPanel.widthAnchor).isActive = true
        listButtons.widthAnchor.constraint(equalTo: listPanel.widthAnchor).isActive = true
        listPanel.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let editorPanel = buildRuleEditor()
        editorPanel.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        let contentRow = NSStackView(views: [listPanel, divider, editorPanel])
        contentRow.orientation = .horizontal
        contentRow.alignment = .top
        contentRow.spacing = 18
        contentRow.distribution = .fill

        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalTo: contentRow.heightAnchor).isActive = true
        editorPanel.widthAnchor.constraint(greaterThanOrEqualToConstant: 390).isActive = true

        statusLabel.textColor = .systemRed
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let cancelButton = NSButton(title: "Отмена", target: self, action: #selector(cancel))
        let saveButton = NSButton(title: "Сохранить", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"

        let footer = NSStackView(views: [statusLabel, NSView(), cancelButton, saveButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10

        let mainStack = NSStackView(views: [header, contentRow, footer])
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 18
        root.addSubview(mainStack)

        header.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        settingsRow.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        contentRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        footer.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            mainStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            mainStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            contentRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 330),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280)
        ])
    }

    private func buildRuleEditor() -> NSView {
        let container = NSView()

        let sectionTitle = NSTextField(labelWithString: "Параметры интервала")
        sectionTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        ruleEnabled.target = self
        ruleEnabled.action = #selector(updateSelectedRule)

        let daysLabel = formLabel("Дни недели")
        let daysRow = NSStackView()
        daysRow.orientation = .horizontal
        daysRow.alignment = .centerY
        daysRow.spacing = 6

        for (index, title) in ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"].enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(updateSelectedRule))
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .rounded
            button.tag = index + 1
            button.widthAnchor.constraint(equalToConstant: 42).isActive = true
            dayButtons.append(button)
            daysRow.addArrangedSubview(button)
        }

        configureTimePicker(startPicker)
        configureTimePicker(endPicker)

        let startGroup = formGroup(title: "Начало", control: startPicker)
        let endGroup = formGroup(title: "Конец", control: endPicker)
        let timeRow = NSStackView(views: [startGroup, endGroup])
        timeRow.orientation = .horizontal
        timeRow.alignment = .top
        timeRow.spacing = 18
        timeRow.distribution = .fillEqually

        modePopup.addItems(withTitles: modeItems.map(\.0))
        modePopup.target = self
        modePopup.action = #selector(updateSelectedRule)
        let modeGroup = formGroup(title: "Режим индикатора", control: modePopup)

        let hint = NSTextField(wrappingLabelWithString: "Интервалы могут переходить через полночь. Например, 23:00–08:00 действует ночью.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView(views: [sectionTitle, ruleEnabled, daysLabel, daysRow, timeRow, modeGroup, hint, NSView()])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        container.addSubview(stack)

        daysRow.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
        timeRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        modeGroup.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        hint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func formLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        return label
    }

    private func formGroup(title: String, control: NSView) -> NSStackView {
        let stack = NSStackView(views: [formLabel(title), control])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func configureTimePicker(_ picker: NSDatePicker) {
        picker.datePickerElements = [.hourMinute]
        picker.datePickerStyle = .textFieldAndStepper
        picker.target = self
        picker.action = #selector(updateSelectedRule)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { schedule.rules.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard schedule.rules.indices.contains(row) else { return nil }
        let rule = schedule.rules[row]
        let identifier = NSUserInterfaceItemIdentifier("ScheduleRuleCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? makeRuleCell(identifier: identifier)
        guard let title = cell.textField, let subtitle = cell.viewWithTag(1001) as? NSTextField else { return cell }

        title.stringValue = "\(compactDays(rule.days))  ·  \(rule.start.stringValue)–\(rule.end.stringValue)"
        subtitle.stringValue = modeItems.first(where: { $0.1 == rule.mode })?.0 ?? rule.mode.rawValue
        title.textColor = rule.enabled ? .labelColor : .secondaryLabelColor
        subtitle.textColor = .secondaryLabelColor
        return cell
    }

    private func makeRuleCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: "")
        subtitle.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.tag = 1001
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        cell.textField = title
        cell.addSubview(title)
        cell.addSubview(subtitle)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 7),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            subtitle.bottomAnchor.constraint(lessThanOrEqualTo: cell.bottomAnchor, constant: -6)
        ])
        return cell
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
        table.scrollRowToVisible(index)
        isChangingSelection = false
        loadRule(at: index)
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
        removeButton.isEnabled = true
        statusLabel.stringValue = ""
    }

    private func setEditorEnabled(_ value: Bool) {
        ruleEnabled.isEnabled = value
        dayButtons.forEach { $0.isEnabled = value }
        startPicker.isEnabled = value
        endPicker.isEnabled = value
        modePopup.isEnabled = value
        removeButton.isEnabled = value
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
                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
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
