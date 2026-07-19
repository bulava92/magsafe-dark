import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum IconStyle: String { case monochrome, actualColor }
    private enum AppLanguage: String { case ru, en }

    private let helper = "/usr/local/libexec/magsafe-led-helper"
    private let automationCLI = "/usr/local/bin/magsafe-dark"
    private let defaults = UserDefaults.standard
    private let menu = NSMenu()
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var isReapplyingMode = false

    private let iconStyleKey = "statusIconStyle"
    private let rememberedModeKey = "rememberedLEDMode"
    private let restoreModeKey = "restoreLEDModeAtLaunch"
    private let successSecondsKey = "codexSuccessSeconds"
    private let errorSecondsKey = "codexErrorSeconds"
    private let notificationsKey = "codexNotifications"
    private let languageKey = "appLanguage"
    private let showTimerInStatusBarKey = "showTimerInStatusBar"
    private let showTimerInMenuKey = "showTimerInMenu"

    func applicationDidFinishLaunching(_ notification: Notification) {
        if defaults.object(forKey: languageKey) == nil {
            let systemLanguage: AppLanguage = Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") == true ? .ru : .en
            defaults.set(systemLanguage.rawValue, forKey: languageKey)
        }

        defaults.register(defaults: [
            restoreModeKey: false,
            successSecondsKey: 5,
            errorSecondsKey: 5,
            notificationsKey: true,
            showTimerInStatusBarKey: false,
            showTimerInMenuKey: false
        ])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        statusItem.menu = menu

        if defaults.bool(forKey: restoreModeKey),
           let mode = defaults.string(forKey: rememberedModeKey) {
            _ = run(automationCLI, [mode])
        }

        refreshStatusNow()
        rebuildMenu()
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(refreshStatus),
            userInfo: nil,
            repeats: true
        )
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatusNow()
        rebuildMenu()
    }

    private var language: AppLanguage {
        get { AppLanguage(rawValue: defaults.string(forKey: languageKey) ?? "en") ?? .en }
        set { defaults.set(newValue.rawValue, forKey: languageKey) }
    }

    private func text(_ ru: String, _ en: String) -> String {
        language == .ru ? ru : en
    }

    private var iconStyle: IconStyle {
        get { IconStyle(rawValue: defaults.string(forKey: iconStyleKey) ?? "") ?? .monochrome }
        set { defaults.set(newValue.rawValue, forKey: iconStyleKey) }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let mode = currentMode()
        let remaining = timerRemaining()

        let status = NSMenuItem(
            title: text("Текущий режим: \(modeName(mode))", "Current mode: \(modeName(mode))"),
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)

        if defaults.bool(forKey: showTimerInMenuKey), let remaining {
            let timerStatus = NSMenuItem(
                title: text("Осталось по таймеру: \(formatDuration(remaining))", "Timer remaining: \(formatDuration(remaining))"),
                action: nil,
                keyEquivalent: ""
            )
            timerStatus.isEnabled = false
            menu.addItem(timerStatus)
        }

        menu.addItem(.separator())

        let toggle = mode == 1
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
        timers.addItem(timerItem(text("Выключить на 15 минут", "Turn off for 15 minutes"), seconds: 900, mode: "off"))
        timers.addItem(timerItem(text("Выключить на 1 час", "Turn off for 1 hour"), seconds: 3600, mode: "off"))
        timers.addItem(timerItem(text("Оранжевая на 15 минут", "Orange for 15 minutes"), seconds: 900, mode: "orange"))
        if remaining != nil {
            timers.addItem(.separator())
            timers.addItem(item(text("Отменить таймер", "Cancel timer"), #selector(cancelTimer)))
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
        let colored = item(text("Подсвечивать колбу цветом LED", "Color the bulb using the LED color"), #selector(useActualColorIcon))
        colored.state = iconStyle == .actualColor ? .on : .off
        appearance.addItem(colored)
        settings.addItem(submenu(text("Вид значка", "Icon appearance"), appearance))

        let timerDisplay = NSMenu()
        let statusBarTimer = item(text("Показывать рядом с лампочкой", "Show next to the bulb"), #selector(toggleTimerInStatusBar))
        statusBarTimer.state = defaults.bool(forKey: showTimerInStatusBarKey) ? .on : .off
        timerDisplay.addItem(statusBarTimer)
        let menuTimer = item(text("Показывать под текущим режимом", "Show below the current mode"), #selector(toggleTimerInMenu))
        menuTimer.state = defaults.bool(forKey: showTimerInMenuKey) ? .on : .off
        timerDisplay.addItem(menuTimer)
        settings.addItem(submenu(text("Остаток таймера", "Timer countdown"), timerDisplay))

        let codex = NSMenu()
        codex.addItem(durationItem(text("5 секунд", "5 seconds"), seconds: 5))
        codex.addItem(durationItem(text("10 секунд", "10 seconds"), seconds: 10))
        codex.addItem(durationItem(text("30 секунд", "30 seconds"), seconds: 30))
        let notify = item(text("Уведомления", "Notifications"), #selector(toggleNotifications))
        notify.state = defaults.bool(forKey: notificationsKey) ? .on : .off
        codex.addItem(.separator())
        codex.addItem(notify)
        settings.addItem(submenu(text("Codex-индикация", "Codex indication"), codex))

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
        menu.addItem(item(text("Диагностика…", "Diagnostics…"), #selector(showDiagnostics)))
        menu.addItem(item(text("Проверить обновления…", "Check for updates…"), #selector(checkUpdates)))
        menu.addItem(item(text("Выход", "Quit"), #selector(quit), key: "q"))
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

    private func durationItem(_ title: String, seconds: Int) -> NSMenuItem {
        let result = item(title, #selector(selectCodexDuration(_:)))
        result.representedObject = seconds
        let selected = defaults.integer(forKey: successSecondsKey) == seconds && defaults.integer(forKey: errorSecondsKey) == seconds
        result.state = selected ? .on : .off
        return result
    }

    private func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return (127, text("Команда не установлена. Запустите install.sh.", "Command is not installed. Run install.sh."))
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
            return (task.terminationStatus, output)
        } catch {
            return (126, error.localizedDescription)
        }
    }

    private func runHelper(_ arguments: [String]) -> (status: Int32, output: String) {
        run("/usr/bin/sudo", ["-n", helper] + arguments)
    }

    private func currentMode() -> UInt8? {
        let result = runHelper(["status"])
        guard result.status == 0 else { return nil }
        return UInt8(result.output)
    }

    private func timerRemaining() -> Int? {
        let result = run(automationCLI, ["timer-status"])
        guard result.status == 0, !result.output.isEmpty, let value = Int(result.output), value > 0 else { return nil }
        return value
    }

    private func temporaryStateIsActive() -> Bool {
        run(automationCLI, ["temporary-active"]).status == 0
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
        default: return text("неизвестен", "unknown")
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    private func updateStatusIcon(mode: UInt8? = nil) {
        let actualMode = mode ?? currentMode()
        let description = "MagSafe LED: \(modeName(actualMode))"

        if iconStyle == .actualColor, let color = bulbColor(for: actualMode),
           let image = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: description) {
            let config = NSImage.SymbolConfiguration(paletteColors: [color, .labelColor])
            let colored = image.withSymbolConfiguration(config) ?? image
            colored.isTemplate = false
            statusItem.button?.image = colored
        } else {
            let symbol = actualMode == 1 ? "lightbulb.slash" : (actualMode == 6 || actualMode == 7 || actualMode == 19 ? "lightbulb.2" : "lightbulb")
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
            image?.isTemplate = true
            statusItem.button?.image = image
        }

        if defaults.bool(forKey: showTimerInStatusBarKey), let remaining = timerRemaining() {
            statusItem.button?.title = "  \(formatDuration(remaining))"
        } else {
            statusItem.button?.title = ""
        }
    }

    private func bulbColor(for mode: UInt8?) -> NSColor? {
        switch mode {
        case 3: return .systemGreen
        case 4, 5, 6, 7, 19: return .systemOrange
        default: return nil
        }
    }

    private func executeState(_ state: String, remember: Bool = true) {
        let result = run(automationCLI, [state])
        guard result.status == 0 else {
            alert(text("Не удалось изменить LED", "Could not change the LED"), result.output.isEmpty ? text("Неизвестная ошибка", "Unknown error") : result.output)
            return
        }
        if remember { defaults.set(state, forKey: rememberedModeKey) }
        refreshStatusNow()
        rebuildMenu()
    }

    private func refreshStatusNow() {
        var mode = currentMode()
        if !isReapplyingMode,
           !temporaryStateIsActive(),
           let remembered = defaults.string(forKey: rememberedModeKey),
           remembered != "system",
           let expected = expectedValue(for: remembered),
           let actual = mode,
           actual != expected {
            isReapplyingMode = true
            let result = run(automationCLI, [remembered])
            isReapplyingMode = false
            if result.status == 0 { mode = expected }
        }
        updateStatusIcon(mode: mode)
    }

    private var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func refreshStatus() { refreshStatusNow() }
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
        let result = run(automationCLI, ["for", String(seconds), mode])
        if result.status != 0 {
            alert(text("Не удалось запустить таймер", "Could not start the timer"), result.output)
            return
        }
        defaults.set("system", forKey: rememberedModeKey)
        refreshStatusNow()
        rebuildMenu()
    }

    @objc private func cancelTimer() {
        let result = run(automationCLI, ["cancel-timer"])
        if result.status != 0 {
            alert(text("Не удалось отменить таймер", "Could not cancel the timer"), result.output)
            return
        }
        defaults.set("system", forKey: rememberedModeKey)
        refreshStatusNow()
        rebuildMenu()
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

    @objc private func toggleTimerInStatusBar() {
        defaults.set(!defaults.bool(forKey: showTimerInStatusBarKey), forKey: showTimerInStatusBarKey)
        refreshStatusNow(); rebuildMenu()
    }

    @objc private func toggleTimerInMenu() {
        defaults.set(!defaults.bool(forKey: showTimerInMenuKey), forKey: showTimerInMenuKey)
        rebuildMenu()
    }

    @objc private func selectCodexDuration(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Int else { return }
        defaults.set(seconds, forKey: successSecondsKey)
        defaults.set(seconds, forKey: errorSecondsKey)
        rebuildMenu()
    }

    @objc private func toggleNotifications() {
        defaults.set(!defaults.bool(forKey: notificationsKey), forKey: notificationsKey)
        rebuildMenu()
    }

    @objc private func useMonochromeIcon() {
        iconStyle = .monochrome
        refreshStatusNow(); rebuildMenu()
    }

    @objc private func useActualColorIcon() {
        iconStyle = .actualColor
        refreshStatusNow(); rebuildMenu()
    }

    @objc private func useRussian() {
        language = .ru
        refreshStatusNow(); rebuildMenu()
    }

    @objc private func useEnglish() {
        language = .en
        refreshStatusNow(); rebuildMenu()
    }

    @objc private func showDiagnostics() {
        let model = run("/usr/sbin/sysctl", ["-n", "hw.model"]).output
        let helperExists = FileManager.default.isExecutableFile(atPath: helper)
        let status = runHelper(["status"])
        let textValue = text(
            "Модель: \(model.isEmpty ? "неизвестна" : model)\nHelper: \(helperExists ? "установлен" : "не найден")\nACLC: \(status.status == 0 ? status.output : "ошибка — \(status.output)")\nПриложение: \(Bundle.main.bundlePath)",
            "Model: \(model.isEmpty ? "unknown" : model)\nHelper: \(helperExists ? "installed" : "not found")\nACLC: \(status.status == 0 ? status.output : "error — \(status.output)")\nApplication: \(Bundle.main.bundlePath)"
        )
        alert(text("Диагностика MagSafe Dark", "MagSafe Dark diagnostics"), textValue)
    }

    @objc private func checkUpdates() {
        NSWorkspace.shared.open(URL(string: "https://github.com/bulava92/magsafe-dark/releases/latest")!)
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
