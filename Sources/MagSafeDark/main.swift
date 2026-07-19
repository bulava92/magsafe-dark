import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum IconStyle: String {
        case monochrome
        case actualColor
    }

    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private let helper = "/usr/local/libexec/magsafe-led-helper"
    private let automationCLI = "/usr/local/bin/magsafe-dark"
    private let menu = NSMenu()
    private let iconStyleKey = "statusIconStyle"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        statusItem.menu = menu

        updateStatusIcon()
        rebuildMenu()

        refreshTimer = Timer.scheduledTimer(
            timeInterval: 1.0,
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
            guard let rawValue = UserDefaults.standard.string(forKey: iconStyleKey),
                  let style = IconStyle(rawValue: rawValue) else {
                return .monochrome
            }
            return style
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: iconStyleKey)
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let mode = currentMode()
        if mode == 1 {
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

        let appearance = NSMenu()
        let monochromeItem = item("Чёрно-белый", #selector(useMonochromeIcon))
        monochromeItem.state = iconStyle == .monochrome ? .on : .off
        appearance.addItem(monochromeItem)

        let actualColorItem = item("Показывать реальный цвет LED", #selector(useActualColorIcon))
        actualColorItem.state = iconStyle == .actualColor ? .on : .off
        appearance.addItem(actualColorItem)

        let appearanceItem = NSMenuItem(title: "Вид значка", action: nil, keyEquivalent: "")
        appearanceItem.submenu = appearance
        menu.addItem(appearanceItem)

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
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

    private func updateStatusIcon() {
        let mode = currentMode()
        let symbolName = mode == 1 ? "lightbulb.slash.fill" : "lightbulb.fill"
        let description = accessibilityDescription(for: mode)

        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description) else {
            statusItem.button?.image = nil
            return
        }

        if iconStyle == .actualColor {
            let color: NSColor
            switch mode {
            case 3:
                color = .systemGreen
            case 4:
                color = .systemOrange
            case 1:
                color = .secondaryLabelColor
            default:
                color = .labelColor
            }

            let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
            let coloredImage = image.withSymbolConfiguration(configuration) ?? image
            coloredImage.isTemplate = false
            statusItem.button?.image = coloredImage
        } else {
            image.isTemplate = true
            statusItem.button?.image = image
        }
    }

    private func accessibilityDescription(for mode: UInt8?) -> String {
        switch mode {
        case 0:
            return "MagSafe LED: штатный режим"
        case 1:
            return "MagSafe LED: выключен"
        case 3:
            return "MagSafe LED: зелёный"
        case 4:
            return "MagSafe LED: оранжевый"
        default:
            return "MagSafe LED: состояние неизвестно"
        }
    }

    private func executeState(_ state: String) {
        let result = run(automationCLI, [state])
        guard result.status == 0 else {
            alert("Не удалось изменить LED", result.output.isEmpty ? "Неизвестная ошибка" : result.output)
            return
        }

        updateStatusIcon()
        rebuildMenu()
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func refreshStatus() {
        updateStatusIcon()
    }

    @objc private func turnOff() { executeState("off") }
    @objc private func systemMode() { executeState("system") }
    @objc private func green() { executeState("green") }
    @objc private func orange() { executeState("orange") }

    @objc private func useMonochromeIcon() {
        iconStyle = .monochrome
        updateStatusIcon()
        rebuildMenu()
    }

    @objc private func useActualColorIcon() {
        iconStyle = .actualColor
        updateStatusIcon()
        rebuildMenu()
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
