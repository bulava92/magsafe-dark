import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let helper = "/usr/local/libexec/magsafe-led-helper"
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

    private func runHelper(_ arguments: [String]) -> (status: Int32, output: String) {
        guard FileManager.default.isExecutableFile(atPath: helper) else {
            return (127, "Helper не установлен. Запустите install.sh.")
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", helper] + arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (task.terminationStatus, output)
        } catch {
            return (126, error.localizedDescription)
        }
    }

    private func currentMode() -> UInt8? {
        let result = runHelper(["status"])
        guard result.status == 0 else { return nil }
        return UInt8(result.output)
    }

    private func setLED(_ mode: String) {
        let result = runHelper([mode])
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

    @objc private func turnOff() { setLED("off") }
    @objc private func systemMode() { setLED("system") }
    @objc private func green() { setLED("green") }
    @objc private func orange() { setLED("orange") }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
