import AppKit
import Foundation
import IOKit.ps
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum IconStyle: String { case monochrome, actualColor }
    private enum AppLanguage: String { case ru, en }

    private struct CommandResult {
        let status: Int32
        let output: String
    }

    private struct Snapshot {
        let mode: UInt8?
        let remaining: Int?
        let temporary: Bool
        let timerEnd: Date?
        let batteryPercent: Int?
        let onACPower: Bool?
        let isCharging: Bool?
        let chargeCompletion: Date?
    }

    private let helper = "/usr/local/libexec/magsafe-led-client"
    private let automationCLI = "/usr/local/bin/magsafe-dark"
    private let defaults = UserDefaults.standard
    private let menu = NSMenu()
    private let commandQueue = DispatchQueue(label: "su.xyz.MagSafeDark.commands", qos: .utility)

    private var statusItem: NSStatusItem!
    private weak var statusContentStack: NSStackView?
    private weak var statusBatteryImageView: NSImageView?
    private weak var statusTextField: NSTextField?
    private weak var statusPlugImageView: NSImageView?
    private var refreshTimer: Timer?
    private var appearanceObservation: NSKeyValueObservation?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var refreshInFlight = false
    private var menuIsOpen = false
    private var cachedMode: UInt8?
    private var cachedTimerRemaining: Int?
    private var cachedTimerEnd: Date?
    private var cachedTemporaryActive = false
    private var cachedBatteryPercent: Int?
    private var cachedOnACPower: Bool?
    private var cachedIsCharging: Bool?
    private var cachedChargeCompletion: Date?

    private weak var currentModeMenuItem: NSMenuItem?
    private weak var timerCountdownMenuItem: NSMenuItem?
    private weak var cancelTimerMenuItem: NSMenuItem?

    private let iconStyleKey = "statusIconStyle"
    private let rememberedModeKey = "rememberedLEDMode"
    private let restoreModeKey = "restoreLEDModeAtLaunch"
    private let successSecondsKey = "codexSuccessSeconds"
    private let errorSecondsKey = "codexErrorSeconds"
    private let notificationsKey = "codexNotifications"
    private let successNotificationsKey = "codexSuccessNotifications"
    private let errorNotificationsKey = "codexErrorNotifications"
    private let workingModeKey = "codexWorkingMode"
    private let successModeKey = "codexSuccessMode"
    private let errorModeKey = "codexErrorMode"
    private let languageKey = "appLanguage"
    private let showTimerInStatusBarKey = "showTimerInStatusBar"
    private let showTimerInMenuKey = "showTimerInMenu"
    private let showBatteryPercentageKey = "showBatteryPercentageInStatusBar"
    private let showChargingStateKey = "showChargingStateInStatusBar"
    private let showChargeCompletionKey = "showChargeCompletionInStatusBar"

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard enforceSingleInstance() else { return }

        if defaults.object(forKey: languageKey) == nil {
            let systemLanguage: AppLanguage = Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") == true ? .ru : .en
            defaults.set(systemLanguage.rawValue, forKey: languageKey)
        }

        defaults.register(defaults: [
            restoreModeKey: false,
            successSecondsKey: 5,
            errorSecondsKey: 5,
            notificationsKey: true,
            successNotificationsKey: true,
            errorNotificationsKey: true,
            workingModeKey: "orange",
            successModeKey: "green",
            errorModeKey: "orange",
            showTimerInStatusBarKey: false,
            showTimerInMenuKey: false,
            showBatteryPercentageKey: false,
            showChargingStateKey: false,
            showChargeCompletionKey: false
        ])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        statusItem.menu = menu
        installAppearanceObserver()
        installNativePowerSourceObserver()

        updateStatusIcon(mode: nil, remaining: nil)
        rebuildMenu()
        registerSystemNotifications()

        if defaults.bool(forKey: restoreModeKey), let mode = defaults.string(forKey: rememberedModeKey) {
            executeState(mode, remember: false)
        } else {
            requestRefresh(force: true)
        }

        updateRefreshTimer()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        rebuildMenu()
        requestRefresh(force: true)
        updateRefreshTimer()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        updateRefreshTimer()
    }

    private func enforceSingleInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            existing.activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil)
            return false
        }
        return true
    }

    private func installAppearanceObserver() {
        appearanceObservation = statusItem.button?.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            guard let self else { return }
            self.updateStatusIcon(mode: self.cachedMode, remaining: self.cachedTimerRemaining)
            self.rebuildMenu()
        }
    }

    private func installNativePowerSourceObserver() {
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

    private func registerSystemNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    private var language: AppLanguage {
        get { AppLanguage(rawValue: defaults.string(forKey: languageKey) ?? "en") ?? .en }
        set { defaults.set(newValue.rawValue, forKey: languageKey) }
    }

    private func text(_ ru: String, _ en: String) -> String { language == .ru ? ru : en }

    private var iconStyle: IconStyle {
        get { IconStyle(rawValue: defaults.string(forKey: iconStyleKey) ?? "") ?? .monochrome }
        set { defaults.set(newValue.rawValue, forKey: iconStyleKey) }
    }

    private func rebuildMenu() {
        currentModeMenuItem = nil
        timerCountdownMenuItem = nil
        cancelTimerMenuItem = nil
        menu.removeAllItems()

        let status = NSMenuItem(title: currentModeTitle(cachedMode), action: nil, keyEquivalent: "")
        status.isEnabled = false
        currentModeMenuItem = status
        menu.addItem(status)

        if defaults.bool(forKey: showTimerInMenuKey), let remaining = cachedTimerRemaining {
            let timerStatus = NSMenuItem(title: timerRemainingTitle(remaining), action: nil, keyEquivalent: "")
            timerStatus.isEnabled = false
            timerCountdownMenuItem = timerStatus
            menu.addItem(timerStatus)
        }

        menu.addItem(.separator())

        let toggle = cachedMode == 1
            ? item(text("Вернуть штатный режим", "Restore system mode"), #selector(systemMode), key: "0")
            : item(text("Выключить лампочку", "Turn LED off"), #selector(turnOff), key: "0")
        toggle.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(toggle)

        let colors = NSMenu()
        colors.addItem(modeItem(text("Зелёная", "Green"), mode: "green", key: "g"))
        colors.addItem(modeItem(text("Оранжевая", "Orange"), mode: "orange", key: "o"))
        menu.addItem(submenu(text("Принудительный цвет", "Force color"), colors))

        let effects = NSMenu()
        effects.addItem(modeItem(text("Одиночная индикация", "Single indication"), mode: "flash"))
        effects.addItem(modeItem(text("Медленное мигание", "Slow blinking"), mode: "blink-slow"))
        effects.addItem(modeItem(text("Быстрое мигание", "Fast blinking"), mode: "blink-fast"))
        effects.addItem(modeItem(text("Мигание с выключением", "Blink, then turn off"), mode: "blink-off"))
        menu.addItem(submenu(text("Эффекты", "Effects"), effects))

        let timers = NSMenu()
        timers.addItem(timerItem(text("Выключить на 5 минут", "Turn off for 5 minutes"), seconds: 300, mode: "off"))
        timers.addItem(timerItem(text("Выключить на 15 минут", "Turn off for 15 minutes"), seconds: 900, mode: "off"))
        timers.addItem(timerItem(text("Выключить на 30 минут", "Turn off for 30 minutes"), seconds: 1800, mode: "off"))
        timers.addItem(timerItem(text("Выключить на 1 час", "Turn off for 1 hour"), seconds: 3600, mode: "off"))
        timers.addItem(.separator())
        timers.addItem(timerItem(text("Оранжевая на 15 минут", "Orange for 15 minutes"), seconds: 900, mode: "orange"))
        timers.addItem(item(text("Другой таймер…", "Custom timer…"), #selector(customTimer)))
        if cachedTimerRemaining != nil {
            timers.addItem(.separator())
            let cancel = item(text("Отменить таймер", "Cancel timer"), #selector(cancelTimer))
            cancelTimerMenuItem = cancel
            timers.addItem(cancel)
        }
        menu.addItem(submenu(text("Таймер", "Timer"), timers))

        let settings = NSMenu()
        let login = item(text("Запускать при входе", "Launch at login"), #selector(toggleLaunchAtLogin))
        login.state = launchAtLoginEnabled ? .on : .off
        settings.addItem(login)

        let restore = item(text("Восстанавливать выбранный режим при запуске", "Restore selected mode at launch"), #selector(toggleRestoreMode))
        restore.state = defaults.bool(forKey: restoreModeKey) ? .on : .off
        settings.addItem(restore)
        settings.addItem(.separator())

        let appearance = NSMenu()
        let monochrome = item(text("Чёрно-белый", "Monochrome"), #selector(useMonochromeIcon))
        monochrome.state = iconStyle == .monochrome ? .on : .off
        appearance.addItem(monochrome)
        let colored = item(text("Подсвечивать значок цветом LED", "Color the icon using the LED color"), #selector(useActualColorIcon))
        colored.state = iconStyle == .actualColor ? .on : .off
        appearance.addItem(colored)
        settings.addItem(submenu(text("Вид значка", "Icon appearance"), appearance))

        let batteryPercentage = item(text("Показывать процент заряда", "Show battery percentage"), #selector(toggleBatteryPercentage))
        batteryPercentage.state = defaults.bool(forKey: showBatteryPercentageKey) ? .on : .off
        settings.addItem(batteryPercentage)


        let chargeCompletion = item(text("Показывать время окончания зарядки", "Show charge completion time"), #selector(toggleChargeCompletion))
        chargeCompletion.state = defaults.bool(forKey: showChargeCompletionKey) ? .on : .off
        settings.addItem(chargeCompletion)

        let timerDisplay = NSMenu()
        let statusBarTimer = item(text("Показывать рядом с лампочкой", "Show next to the bulb"), #selector(toggleTimerInStatusBar))
        statusBarTimer.state = defaults.bool(forKey: showTimerInStatusBarKey) ? .on : .off
        timerDisplay.addItem(statusBarTimer)
        let menuTimer = item(text("Показывать под текущим режимом", "Show below the current mode"), #selector(toggleTimerInMenu))
        menuTimer.state = defaults.bool(forKey: showTimerInMenuKey) ? .on : .off
        timerDisplay.addItem(menuTimer)
        settings.addItem(submenu(text("Остаток таймера", "Timer countdown"), timerDisplay))

        settings.addItem(codexSettingsItem())

        let languages = NSMenu()
        let russian = item("Русский", #selector(useRussian))
        russian.state = language == .ru ? .on : .off
        languages.addItem(russian)
        let english = item("English", #selector(useEnglish))
        english.state = language == .en ? .on : .off
        languages.addItem(english)
        settings.addItem(submenu(text("Язык", "Language"), languages))

        menu.addItem(submenu(text("Настройки", "Settings"), settings))
        menu.addItem(.separator())
        menu.addItem(item(text("Настроить расписание…", "Configure schedule…"), #selector(openScheduleEditor)))
        menu.addItem(item(text("Диагностика…", "Diagnostics…"), #selector(showDiagnostics)))
        menu.addItem(item(text("Открыть журнал", "Open log"), #selector(openLog)))
        menu.addItem(item(text("Проверить обновления…", "Check for updates…"), #selector(checkUpdates)))
        menu.addItem(item(text("Выход", "Quit"), #selector(quit), key: "q"))
    }

    private func codexSettingsItem() -> NSMenuItem {
        let root = NSMenu()
        root.addItem(modeSelectionSubmenu(text("Во время работы", "While working"), key: workingModeKey))
        root.addItem(modeSelectionSubmenu(text("При успехе", "On success"), key: successModeKey))
        root.addItem(modeSelectionSubmenu(text("При ошибке", "On error"), key: errorModeKey))
        root.addItem(.separator())
        root.addItem(durationSelectionSubmenu(text("Длительность успеха", "Success duration"), key: successSecondsKey))
        root.addItem(durationSelectionSubmenu(text("Длительность ошибки", "Error duration"), key: errorSecondsKey))
        root.addItem(.separator())

        let successNotify = item(text("Уведомлять об успехе", "Notify on success"), #selector(toggleCodexNotification(_:)))
        successNotify.representedObject = successNotificationsKey
        successNotify.state = defaults.bool(forKey: successNotificationsKey) ? .on : .off
        root.addItem(successNotify)

        let errorNotify = item(text("Уведомлять об ошибке", "Notify on error"), #selector(toggleCodexNotification(_:)))
        errorNotify.representedObject = errorNotificationsKey
        errorNotify.state = defaults.bool(forKey: errorNotificationsKey) ? .on : .off
        root.addItem(errorNotify)

        return submenu(text("Codex-индикация", "Codex indication"), root)
    }

    private func modeSelectionSubmenu(_ title: String, key: String) -> NSMenuItem {
        let child = NSMenu()
        for (labelRU, labelEN, value) in [
            ("Штатный", "System", "system"),
            ("Выключен", "Off", "off"),
            ("Зелёный", "Green", "green"),
            ("Оранжевый", "Orange", "orange"),
            ("Медленное мигание", "Slow blinking", "blink-slow"),
            ("Быстрое мигание", "Fast blinking", "blink-fast")
        ] {
            let entry = item(text(labelRU, labelEN), #selector(selectCodexMode(_:)))
            entry.representedObject = ["key": key, "value": value]
            entry.state = defaults.string(forKey: key) == value ? .on : .off
            child.addItem(entry)
        }
        return submenu(title, child)
    }

    private func durationSelectionSubmenu(_ title: String, key: String) -> NSMenuItem {
        let child = NSMenu()
        for seconds in [3, 5, 10, 30, 60] {
            let entry = item(text("\(seconds) секунд", "\(seconds) seconds"), #selector(selectCodexDuration(_:)))
            entry.representedObject = ["key": key, "seconds": seconds] as [String: Any]
            entry.state = defaults.integer(forKey: key) == seconds ? .on : .off
            child.addItem(entry)
        }
        return submenu(title, child)
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
        result.target = self
        return result
    }

    private func submenu(_ title: String, _ child: NSMenu) -> NSMenuItem {
        let result = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        result.submenu = child
        return result
    }

    private func modeItem(_ title: String, mode: String, key: String = "") -> NSMenuItem {
        let result = item(title, #selector(selectMode(_:)), key: key)
        result.representedObject = mode
        if !key.isEmpty { result.keyEquivalentModifierMask = [.command, .shift] }
        return result
    }

    private func timerItem(_ title: String, seconds: Int, mode: String) -> NSMenuItem {
        let result = item(title, #selector(selectTimer(_:)))
        result.representedObject = ["seconds": seconds, "mode": mode] as [String: Any]
        return result
    }

    private func run(_ executable: String, _ arguments: [String]) -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return CommandResult(status: 127, output: text("Команда не установлена. Запустите install.sh.", "Command is not installed. Run install.sh."))
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CommandResult(status: task.terminationStatus, output: output)
        } catch {
            return CommandResult(status: 126, output: error.localizedDescription)
        }
    }

    private func readBatteryStatus() -> (percentage: Int?, onACPower: Bool?, isCharging: Bool?, chargeCompletion: Date?) {
        let result = run("/usr/bin/pmset", ["-g", "batt"])
        guard result.status == 0 else { return (nil, nil, nil, nil) }

        var percentage: Int?
        if let expression = try? NSRegularExpression(pattern: #"(\d{1,3})%"#),
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
           let expression = try? NSRegularExpression(pattern: #"(\d+):(\d{2}) remaining"#),
           let match = expression.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let hourRange = Range(match.range(at: 1), in: lower),
           let minuteRange = Range(match.range(at: 2), in: lower),
           let hours = Int(lower[hourRange]),
           let minutes = Int(lower[minuteRange]) {
            chargeCompletion = Date().addingTimeInterval(TimeInterval(hours * 3600 + minutes * 60))
        }

        return (percentage, onACPower, isCharging, chargeCompletion)
    }

    private func readSnapshot() -> Snapshot {
        let modeResult = run(helper, ["status"])
        let timerResult = run(automationCLI, ["timer-status"])
        let temporaryResult = run(automationCLI, ["temporary-active"])
        let timerEndResult = run(automationCLI, ["timer-end"])
        let batteryStatus = readBatteryStatus()
        let mode = modeResult.status == 0 ? UInt8(modeResult.output) : nil
        let remaining = timerResult.status == 0 ? Int(timerResult.output).flatMap { $0 > 0 ? $0 : nil } : nil
        let end = timerEndResult.status == 0 ? TimeInterval(timerEndResult.output).map(Date.init(timeIntervalSince1970:)) : nil
        return Snapshot(mode: mode, remaining: remaining, temporary: temporaryResult.status == 0, timerEnd: end, batteryPercent: batteryStatus.percentage, onACPower: batteryStatus.onACPower, isCharging: batteryStatus.isCharging, chargeCompletion: batteryStatus.chargeCompletion)
    }

    private func requestRefresh(force: Bool = false) {
        guard force || !refreshInFlight else { return }
        refreshInFlight = true
        commandQueue.async { [weak self] in
            guard let self else { return }
            var snapshot = self.readSnapshot()

            if !snapshot.temporary,
               let remembered = self.defaults.string(forKey: self.rememberedModeKey),
               remembered != "system",
               let expected = self.expectedValue(for: remembered),
               let actual = snapshot.mode,
               actual != expected {
                let result = self.run(self.automationCLI, [remembered])
                if result.status == 0 {
                    snapshot = Snapshot(mode: expected, remaining: snapshot.remaining, temporary: snapshot.temporary, timerEnd: snapshot.timerEnd, batteryPercent: snapshot.batteryPercent, onACPower: snapshot.onACPower, isCharging: snapshot.isCharging, chargeCompletion: snapshot.chargeCompletion)
                }
            }

            DispatchQueue.main.async {
                self.refreshInFlight = false
                self.cachedMode = snapshot.mode
                self.cachedTimerRemaining = snapshot.remaining
                self.cachedTemporaryActive = snapshot.temporary
                self.cachedTimerEnd = snapshot.timerEnd
                self.cachedBatteryPercent = snapshot.batteryPercent
                self.cachedOnACPower = snapshot.onACPower
                self.cachedIsCharging = snapshot.isCharging
                self.cachedChargeCompletion = snapshot.chargeCompletion
                self.updateStatusIcon(mode: snapshot.mode, remaining: snapshot.remaining)
                self.updateOpenMenu(mode: snapshot.mode, remaining: snapshot.remaining)
                self.updateRefreshTimer()
            }
        }
    }

    private func updateRefreshTimer() {
        refreshTimer?.invalidate()
        let interval: TimeInterval = (cachedTimerRemaining != nil || menuIsOpen) ? 1 : 15
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(refreshStatus), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func expectedValue(for mode: String) -> UInt8? {
        ["system": 0, "off": 1, "green": 3, "orange": 4, "flash": 5, "blink-slow": 6, "blink-fast": 7, "blink-off": 19][mode]
    }

    private func modeName(_ mode: UInt8?) -> String {
        switch mode {
        case 0: return text("штатный", "system controlled")
        case 1: return text("выключен", "off")
        case 3: return text("зелёный", "green")
        case 4: return text("оранжевый", "orange")
        case 5: return text("одиночная индикация", "single indication")
        case 6: return text("медленное мигание", "slow blinking")
        case 7: return text("быстрое мигание", "fast blinking")
        case 19: return text("мигание с выключением", "blink, then off")
        default: return text("недоступен", "unavailable")
        }
    }

    private func currentModeTitle(_ mode: UInt8?) -> String {
        text("Текущий режим: \(modeName(mode))", "Current mode: \(modeName(mode))")
    }

    private func timerRemainingTitle(_ seconds: Int) -> String {
        if let end = cachedTimerEnd {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return text("Осталось: \(formatDuration(seconds)), до \(formatter.string(from: end))", "Remaining: \(formatDuration(seconds)), until \(formatter.string(from: end))")
        }
        return text("Осталось по таймеру: \(formatDuration(seconds))", "Timer remaining: \(formatDuration(seconds))")
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    private enum BatteryStatusIconKind {
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
        image.isTemplate = false
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

    private func drawBoringNotchAsset(_ source: NSImage, centeredIn frame: NSRect) {
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

    private func appleBatterySymbolName(percent: Int, isCharging: Bool) -> String {
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

    private func updateOpenMenu(mode: UInt8?, remaining: Int?) {
        guard menuIsOpen else { return }
        currentModeMenuItem?.title = currentModeTitle(mode)
        if let remaining {
            timerCountdownMenuItem?.title = timerRemainingTitle(remaining)
            timerCountdownMenuItem?.isHidden = !defaults.bool(forKey: showTimerInMenuKey)
            cancelTimerMenuItem?.isHidden = false
        } else {
            timerCountdownMenuItem?.isHidden = true
            cancelTimerMenuItem?.isHidden = true
        }
        menu.update()
    }

    private func bulbColor(for mode: UInt8?) -> NSColor? {
        switch mode {
        case 3: return .systemGreen
        case 4, 5, 6, 7, 19: return .systemOrange
        default: return nil
        }
    }

    private func executeState(_ state: String, remember: Bool = true) {
        if remember { defaults.set(state, forKey: rememberedModeKey) }
        commandQueue.async { [weak self] in
            guard let self else { return }
            let result = self.run(self.automationCLI, [state])
            DispatchQueue.main.async {
                if result.status != 0 {
                    self.alert(self.text("Не удалось изменить LED", "Could not change the LED"), result.output.isEmpty ? self.text("Неизвестная ошибка", "Unknown error") : result.output)
                }
                self.requestRefresh(force: true)
            }
        }
    }

    private func startTimer(seconds: Int, mode: String) {
        guard seconds > 0 && seconds <= 604800 else {
            alert(text("Неверная длительность", "Invalid duration"), text("Допустимо от 1 секунды до 7 суток.", "Allowed range is 1 second to 7 days."))
            return
        }
        commandQueue.async { [weak self] in
            guard let self else { return }
            let result = self.run(self.automationCLI, ["for", String(seconds), mode])
            DispatchQueue.main.async {
                if result.status != 0 {
                    self.alert(self.text("Не удалось запустить таймер", "Could not start the timer"), result.output)
                }
                self.requestRefresh(force: true)
            }
        }
    }

    private var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func refreshStatus() { requestRefresh() }
    @objc private func systemDidWake() { requestRefresh(force: true) }
    @objc private func turnOff() { executeState("off") }
    @objc private func systemMode() { executeState("system") }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String else { return }
        executeState(mode)
    }

    @objc private func selectTimer(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? [String: Any],
              let seconds = data["seconds"] as? Int,
              let mode = data["mode"] as? String else { return }
        startTimer(seconds: seconds, mode: mode)
    }

    @objc private func customTimer() {
        let alert = NSAlert()
        alert.messageText = text("Другой таймер", "Custom timer")
        alert.informativeText = text("Укажите длительность и режим.", "Choose duration and mode.")
        alert.addButton(withTitle: text("Запустить", "Start"))
        alert.addButton(withTitle: text("Отмена", "Cancel"))

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 92))
        let hours = NSTextField(frame: NSRect(x: 0, y: 58, width: 70, height: 24))
        let minutes = NSTextField(frame: NSRect(x: 82, y: 58, width: 70, height: 24))
        hours.placeholderString = text("Часы", "Hours")
        minutes.placeholderString = text("Минуты", "Minutes")
        hours.stringValue = "0"
        minutes.stringValue = "15"

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 16, width: 200, height: 26), pullsDown: false)
        popup.addItems(withTitles: [text("Выключен", "Off"), text("Зелёный", "Green"), text("Оранжевый", "Orange"), text("Медленное мигание", "Slow blinking"), text("Быстрое мигание", "Fast blinking")])
        popup.item(at: 0)?.representedObject = "off"
        popup.item(at: 1)?.representedObject = "green"
        popup.item(at: 2)?.representedObject = "orange"
        popup.item(at: 3)?.representedObject = "blink-slow"
        popup.item(at: 4)?.representedObject = "blink-fast"

        container.addSubview(hours)
        container.addSubview(minutes)
        container.addSubview(popup)
        alert.accessoryView = container

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let hourValue = Int(hours.stringValue) ?? -1
        let minuteValue = Int(minutes.stringValue) ?? -1
        guard hourValue >= 0, minuteValue >= 0, minuteValue < 60,
              let mode = popup.selectedItem?.representedObject as? String else {
            self.alert(text("Неверные значения", "Invalid values"), text("Минуты должны быть от 0 до 59.", "Minutes must be between 0 and 59."))
            return
        }
        let seconds = hourValue * 3600 + minuteValue * 60
        startTimer(seconds: seconds, mode: mode)
    }

    @objc private func cancelTimer() {
        commandQueue.async { [weak self] in
            guard let self else { return }
            let result = self.run(self.automationCLI, ["cancel-timer"])
            DispatchQueue.main.async {
                if result.status != 0 {
                    self.alert(self.text("Не удалось отменить таймер", "Could not cancel the timer"), result.output)
                }
                self.requestRefresh(force: true)
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            alert(text("Не удалось изменить автозапуск", "Could not change launch-at-login settings"), error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func toggleRestoreMode() {
        defaults.set(!defaults.bool(forKey: restoreModeKey), forKey: restoreModeKey)
        rebuildMenu()
    }

    @objc private func toggleBatteryPercentage() {
        defaults.set(!defaults.bool(forKey: showBatteryPercentageKey), forKey: showBatteryPercentageKey)
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

    @objc private func toggleTimerInStatusBar() {
        defaults.set(!defaults.bool(forKey: showTimerInStatusBarKey), forKey: showTimerInStatusBarKey)
        updateStatusIcon(mode: cachedMode, remaining: cachedTimerRemaining)
        rebuildMenu()
    }

    @objc private func toggleTimerInMenu() {
        defaults.set(!defaults.bool(forKey: showTimerInMenuKey), forKey: showTimerInMenuKey)
        rebuildMenu()
    }

    @objc private func selectCodexMode(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? [String: String],
              let key = data["key"], let value = data["value"] else { return }
        defaults.set(value, forKey: key)
        rebuildMenu()
    }

    @objc private func selectCodexDuration(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? [String: Any],
              let key = data["key"] as? String,
              let seconds = data["seconds"] as? Int else { return }
        defaults.set(seconds, forKey: key)
        rebuildMenu()
    }

    @objc private func toggleCodexNotification(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        defaults.set(!defaults.bool(forKey: key), forKey: key)
        rebuildMenu()
    }

    @objc private func useMonochromeIcon() {
        iconStyle = .monochrome
        updateStatusIcon(mode: cachedMode, remaining: cachedTimerRemaining)
        rebuildMenu()
    }

    @objc private func useActualColorIcon() {
        iconStyle = .actualColor
        updateStatusIcon(mode: cachedMode, remaining: cachedTimerRemaining)
        rebuildMenu()
    }

    @objc private func useRussian() {
        language = .ru
        updateStatusIcon(mode: cachedMode, remaining: cachedTimerRemaining)
        rebuildMenu()
    }

    @objc private func useEnglish() {
        language = .en
        updateStatusIcon(mode: cachedMode, remaining: cachedTimerRemaining)
        rebuildMenu()
    }

    @objc private func openScheduleEditor() {
        let editor = "/usr/local/libexec/magsafe-schedule-editor"
        do {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: editor)
            try task.run()
        } catch {
            alert(text("Не удалось открыть расписание", "Could not open schedule editor"), error.localizedDescription)
        }
    }

    @objc private func showDiagnostics() {
        commandQueue.async { [weak self] in
            guard let self else { return }
            let model = self.run("/usr/sbin/sysctl", ["-n", "hw.model"]).output
            let diagnostics = self.run(self.automationCLI, ["diagnostics"])
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            let os = ProcessInfo.processInfo.operatingSystemVersionString
            let arch = self.run("/usr/bin/uname", ["-m"]).output
            let report = self.text(
                "Версия: \(version)\nmacOS: \(os)\nАрхитектура: \(arch)\nМодель: \(model.isEmpty ? "неизвестна" : model)\n\n\(diagnostics.output)\n\nПриложение: \(Bundle.main.bundlePath)",
                "Version: \(version)\nmacOS: \(os)\nArchitecture: \(arch)\nModel: \(model.isEmpty ? "unknown" : model)\n\n\(diagnostics.output)\n\nApplication: \(Bundle.main.bundlePath)"
            )
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = self.text("Диагностика MagSafe Dark", "MagSafe Dark diagnostics")
                alert.informativeText = report
                alert.addButton(withTitle: self.text("Закрыть", "Close"))
                alert.addButton(withTitle: self.text("Копировать", "Copy"))
                if alert.runModal() == .alertSecondButtonReturn {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
            }
        }
    }

    @objc private func openLog() {
        commandQueue.async { [weak self] in
            guard let self else { return }
            let result = self.run(self.automationCLI, ["log-path"])
            guard result.status == 0, !result.output.isEmpty else { return }
            DispatchQueue.main.async {
                NSWorkspace.shared.open(URL(fileURLWithPath: result.output))
            }
        }
    }

    @objc private func checkUpdates() {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        guard let url = URL(string: "https://api.github.com/repos/bulava92/magsafe-dark/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("MagSafeDark/\(current)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { self.alert(self.text("Проверка обновлений", "Update check"), error.localizedDescription) }
                return
            }
            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = object["tag_name"] as? String else {
                DispatchQueue.main.async { self.alert(self.text("Проверка обновлений", "Update check"), self.text("Не удалось прочитать ответ GitHub.", "Could not read the GitHub response.")) }
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            DispatchQueue.main.async {
                if self.compareVersions(latest, current) == .orderedDescending {
                    let alert = NSAlert()
                    alert.messageText = self.text("Доступна версия \(latest)", "Version \(latest) is available")
                    alert.informativeText = self.text("Установлена версия \(current).", "Installed version: \(current).")
                    alert.addButton(withTitle: self.text("Открыть релиз", "Open release"))
                    alert.addButton(withTitle: self.text("Позже", "Later"))
                    if alert.runModal() == .alertFirstButtonReturn,
                       let releaseURL = URL(string: "https://github.com/bulava92/magsafe-dark/releases/latest") {
                        NSWorkspace.shared.open(releaseURL)
                    }
                } else {
                    self.alert(self.text("Обновление не требуется", "No update available"), self.text("Установлена актуальная версия \(current).", "Version \(current) is up to date."))
                }
            }
        }.resume()
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: .numeric)
    }

    @objc private func quit() {
        refreshTimer?.invalidate()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
