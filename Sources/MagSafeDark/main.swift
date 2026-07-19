import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let helper = "/usr/local/libexec/magsafe-led-helper"
    private let automationCLI = "/usr/local/bin/magsafe-dark"
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "lightbulb.slash",
            accessibilityDescription: "MagSafe Dark"
        )
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        if currentMode() == 1 {
            menu.addItem(item("Вернуть штатный режим", #selector(systemMode)))
        } else {
            menu.addItem(item("Выключить лампочку", #selector(turnOff)))
        }

        let automation = NSMenu()
        automation.addItem(item("Работа — оранжевый", #selector(working)))
        automation.addItem(item("Успех — зелёный", #selector(success)))
        automation.addItem(item("Ошибка — оранжевый", #selector(failure)))
        automation.addItem(item("Ожидание — штатный режим", #selector(idle)))
        let automationItem = NSMenuItem(title: "Состояние автоматизации", action: nil, keyEquivalent: "")
        automationItem.submenu = automation
        menu.addItem(automationItem)

        let colors = NSMenu()
        colors.addItem(item("Зелёная", #selector(green)))
        colors.addItem(item("Оранжевая", #selector(orange)))
        let colorsItem = NSMenuItem(title: "Принудительный цвет", action: nil, keyEquivalent: "")
        colorsItem.submenu = colors
        menu.addItem(colorsItem)

        menu.addItem(.separator())
        menu.addItem(item("Выход", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
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

    private func execute(_ executable: String, _ arguments: [String]) {
        let result = run(executable, arguments)
        guard result.status == 0 else {
            alert("Не удалось изменить LED", result.output.isEmpty ? "Неизвестная ошибка" : result.output)
            return
        }
        rebuildMenu()
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func turnOff() { execute("/usr/bin/sudo", ["-n", helper, "off"]) }
    @objc private func systemMode() { execute("/usr/bin/sudo", ["-n", helper, "system"]) }
    @objc private func green() { execute("/usr/bin/sudo", ["-n", helper, "green"]) }
    @objc private func orange() { execute("/usr/bin/sudo", ["-n", helper, "orange"]) }
    @objc private func working() { execute(automationCLI, ["working"]) }
    @objc private func success() { execute(automationCLI, ["success"]) }
    @objc private func failure() { execute(automationCLI, ["error"]) }
    @objc private func idle() { execute(automationCLI, ["idle"]) }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
