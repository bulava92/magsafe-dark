import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum IconStyle: String { case monochrome, actualColor }

    private let helper = "/usr/local/libexec/magsafe-led-helper"
    private let automationCLI = "/usr/local/bin/magsafe-dark"
    private let defaults = UserDefaults.standard
    private let menu = NSMenu()
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?

    private let iconStyleKey = "statusIconStyle"
    private let rememberedModeKey = "rememberedLEDMode"
    private let restoreModeKey = "restoreLEDModeAtLaunch"
    private let successSecondsKey = "codexSuccessSeconds"
    private let errorSecondsKey = "codexErrorSeconds"
    private let notificationsKey = "codexNotifications"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        statusItem.menu = menu

        defaults.register(defaults: [
            restoreModeKey: false,
            successSecondsKey: 5,
            errorSecondsKey: 5,
            notificationsKey: true
        ])

        if defaults.bool(forKey: restoreModeKey),
           let mode = defaults.string(forKey: rememberedModeKey) {
            _ = run(automationCLI, [mode])
        }

        updateStatusIcon()
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
        updateStatusIcon()
        rebuildMenu()
    }

    private var iconStyle: IconStyle {
        get {
            guard let raw = defaults.string(forKey: iconStyleKey), let value = IconStyle(rawValue: raw) else {
                return .monochrome
            }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: iconStyleKey) }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let mode = currentMode()

        let status = NSMenuItem(title: "Текущий режим: \(modeName(mode))", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let toggle = mode == 1
            ? item("Вернуть штатный режим", #selector(systemMode), key: "0")
            : item("Выключить лампочку", #selector(turnOff), key: "0")
        toggle.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(toggle)

        let colors = NSMenu()
        colors.addItem(modeItem("Зелёная", mode: "green", key: "g"))
        colors.addItem(modeItem("Оранжевая", mode: "orange", key: "o"))
        menu.addItem(submenu("Принудительный цвет", colors))

        let effects = NSMenu()
        effects.addItem(modeItem("Одиночная индикация", mode: "flash"))
        effects.addItem(modeItem("Медленное мигание", mode: "blink-slow"))
        effects.addItem(modeItem("Быстрое мигание", mode: "blink-fast"))
        effects.addItem(modeItem("Мигание с выключением", mode: "blink-off"))
        menu.addItem(submenu("Эффекты", effects))

        let timers = NSMenu()
        timers.addItem(timerItem("Выключить на 15 минут", seconds: 900, mode: "off"))
        timers.addItem(timerItem("Выключить на 1 час", seconds: 3600, mode: "off"))
        timers.addItem(timerItem("Оранжевая на 15 минут", seconds: 900, mode: "orange"))
        timers.addItem(timerItem("Отменить таймер", seconds: 0, mode: "system"))
        menu.addItem(submenu("Таймер", timers))

        let settings = NSMenu()
        let login = item("Запускать при входе", #selector(toggleLaunchAtLogin))
        login.state = launchAtLoginEnabled ? .on : .off
        settings.addItem(login)

        let restore = item("Восстанавливать выбранный режим", #selector(toggleRestoreMode))
        restore.state = defaults.bool(forKey: restoreModeKey) ? .on : .off
        settings.addItem(restore)
        settings.addItem(.separator())

        let appearance = NSMenu()
        let monochrome = item("Чёрно-белый", #selector(useMonochromeIcon))
        monochrome.state = iconStyle == .monochrome ? .on : .off
        appearance.addItem(monochrome)
        let colored = item("Подсвечивать колбу цветом LED", #selector(useActualColorIcon))
        colored.state = iconStyle == .actualColor ? .on : .off
        appearance.addItem(colored)
        settings.addItem(submenu("Вид значка", appearance))

        let codex = NSMenu()
        codex.addItem(durationItem("5 секунд", seconds: 5))
        codex.addItem(durationItem("10 секунд", seconds: 10))
        codex.addItem(durationItem("30 секунд", seconds: 30))
        let notify = item("Уведомления", #selector(toggleNotifications))
        notify.state = defaults.bool(forKey: notificationsKey) ? .on : .off
        codex.addItem(.separator())
        codex.addItem(notify)
        settings.addItem(submenu("Codex-индикация", codex))
        menu.addItem(submenu("Настройки", settings))

        menu.addItem(.separator())
        menu.addItem(item("Диагностика…", #selector(showDiagnostics)))
        menu.addItem(item("Проверить обновления…", #selector(checkUpdates)))
        menu.addItem(item("Выход", #selector(quit), key: "q"))
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
            return (127, "Команда не установлена. Запустите install.sh.")
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

    private func modeName(_ mode: UInt8?) -> String {
        switch mode {
        case 0: return "штатный"
        case 1: return "выключен"
        case 3: return "зелёный"
        case 4: return "оранжевый"
        case 5: return "одиночная индикация"
        case 6: return "медленное мигание"
        case 7: return "быстрое мигание"
        case 19: return "мигание с выключением"
        default: return "неизвестен"
        }
    }

    private func updateStatusIcon() {
        let mode = currentMode()
        let description = "MagSafe LED: \(modeName(mode))"
        if iconStyle == .actualColor, let color = bulbColor(for: mode),
           let image = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: description) {
            let config = NSImage.SymbolConfiguration(paletteColors: [color, .labelColor])
            let colored = image.withSymbolConfiguration(config) ?? image
            colored.isTemplate = false
            statusItem.button?.image = colored
            return
        }

        let symbol = mode == 1 ? "lightbulb.slash" : (mode == 6 || mode == 7 || mode == 19 ? "lightbulb.2" : "lightbulb")
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true
        statusItem.button?.image = image
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
            alert("Не удалось изменить LED", result.output.isEmpty ? "Неизвестная ошибка" : result.output)
            return
        }
        if remember { defaults.set(state, forKey: rememberedModeKey) }
        updateStatusIcon()
        rebuildMenu()
    }

    private var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func refreshStatus() { updateStatusIcon() }
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
        if seconds == 0 {
            executeState("system", remember: false)
        } else {
            let result = run(automationCLI, ["for", String(seconds), mode])
            if result.status != 0 { alert("Не удалось запустить таймер", result.output) }
            updateStatusIcon()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            alert("Не удалось изменить автозапуск", error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func toggleRestoreMode() {
        defaults.set(!defaults.bool(forKey: restoreModeKey), forKey: restoreModeKey)
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
        updateStatusIcon(); rebuildMenu()
    }

    @objc private func useActualColorIcon() {
        iconStyle = .actualColor
        updateStatusIcon(); rebuildMenu()
    }

    @objc private func showDiagnostics() {
        let model = run("/usr/sbin/sysctl", ["-n", "hw.model"]).output
        let helperExists = FileManager.default.isExecutableFile(atPath: helper)
        let status = runHelper(["status"])
        let text = "Модель: \(model.isEmpty ? "неизвестна" : model)\nHelper: \(helperExists ? "установлен" : "не найден")\nACLC: \(status.status == 0 ? status.output : "ошибка — \(status.output)")\nПриложение: \(Bundle.main.bundlePath)"
        alert("Диагностика MagSafe Dark", text)
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