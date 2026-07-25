from pathlib import Path
import re

source_path = Path("Sources/MagSafeDark/main.swift")
source = source_path.read_text()

pattern = re.compile(
    r'    @objc private func checkUpdates\(\) \{.*?\n    private func compareVersions',
    re.S,
)

replacement = r'''    @objc private func checkUpdates() {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        guard let url = URL(string: "https://api.github.com/repos/bulava92/magsafe-dark/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("MagSafeDark/\(current)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.alert(self.text("Проверка обновлений", "Update check"), error.localizedDescription)
                }
                return
            }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = object["tag_name"] as? String else {
                DispatchQueue.main.async {
                    self.alert(
                        self.text("Проверка обновлений", "Update check"),
                        self.text("Не удалось прочитать ответ GitHub.", "Could not read the GitHub response.")
                    )
                }
                return
            }

            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let releaseURL = (object["html_url"] as? String).flatMap(URL.init(string:))
            let assets = object["assets"] as? [[String: Any]] ?? []
            let packageAssets = assets.compactMap { asset -> (name: String, url: URL)? in
                guard let name = asset["name"] as? String,
                      name.lowercased().hasSuffix(".pkg"),
                      let rawURL = asset["browser_download_url"] as? String,
                      let url = URL(string: rawURL) else { return nil }
                return (name, url)
            }
            let package = packageAssets.first {
                $0.name.localizedCaseInsensitiveContains(latest)
            } ?? packageAssets.first

            DispatchQueue.main.async {
                guard self.compareVersions(latest, current) == .orderedDescending else {
                    self.alert(
                        self.text("Обновление не требуется", "No update available"),
                        self.text("Установлена актуальная версия \(current).", "Version \(current) is up to date.")
                    )
                    return
                }

                let alert = NSAlert()
                alert.messageText = self.text("Доступна версия \(latest)", "Version \(latest) is available")
                if package != nil {
                    alert.informativeText = self.text(
                        "Установлена версия \(current). Пакет будет скачан и открыт в стандартном установщике macOS.",
                        "Installed version: \(current). The package will be downloaded and opened in the standard macOS Installer."
                    )
                    alert.addButton(withTitle: self.text("Установить обновление", "Install update"))
                } else {
                    alert.informativeText = self.text(
                        "Установлена версия \(current), но в релизе не найден установочный пакет.",
                        "Installed version: \(current), but the release does not contain an installer package."
                    )
                    alert.addButton(withTitle: self.text("Открыть релиз", "Open release"))
                }
                alert.addButton(withTitle: self.text("Открыть описание", "Open release notes"))
                alert.addButton(withTitle: self.text("Позже", "Later"))

                switch alert.runModal() {
                case .alertFirstButtonReturn:
                    if let package {
                        self.downloadAndOpenUpdate(packageURL: package.url, filename: package.name, version: latest)
                    } else if let releaseURL {
                        NSWorkspace.shared.open(releaseURL)
                    }
                case .alertSecondButtonReturn:
                    if let releaseURL { NSWorkspace.shared.open(releaseURL) }
                default:
                    break
                }
            }
        }.resume()
    }

    private func downloadAndOpenUpdate(packageURL: URL, filename: String, version: String) {
        var request = URLRequest(url: packageURL)
        request.setValue("MagSafeDark/\(version)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.downloadTask(with: request) { [weak self] temporaryURL, response, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.alert(self.text("Не удалось скачать обновление", "Could not download update"), error.localizedDescription)
                }
                return
            }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let temporaryURL else {
                DispatchQueue.main.async {
                    self.alert(
                        self.text("Не удалось скачать обновление", "Could not download update"),
                        self.text("Сервер вернул некорректный ответ.", "The server returned an invalid response.")
                    )
                }
                return
            }

            do {
                let safeFilename = URL(fileURLWithPath: filename).lastPathComponent
                guard safeFilename.lowercased().hasSuffix(".pkg") else {
                    throw NSError(
                        domain: "MagSafeDark.Update",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: self.text("Файл обновления не является пакетом .pkg.", "The update file is not a .pkg package.")]
                    )
                }

                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("MagSafe Dark Updates", isDirectory: true)
                    .appendingPathComponent(version, isDirectory: true)
                try? FileManager.default.removeItem(at: directory)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent(safeFilename)
                try FileManager.default.moveItem(at: temporaryURL, to: destination)

                let values = try destination.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
                    throw NSError(
                        domain: "MagSafeDark.Update",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: self.text("Загруженный пакет пуст или повреждён.", "The downloaded package is empty or damaged.")]
                    )
                }

                DispatchQueue.main.async {
                    if !NSWorkspace.shared.open(destination) {
                        self.alert(
                            self.text("Не удалось открыть установщик", "Could not open Installer"),
                            self.text("Пакет сохранён: \(destination.path)", "The package was saved at: \(destination.path)")
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.alert(self.text("Не удалось подготовить обновление", "Could not prepare update"), error.localizedDescription)
                }
            }
        }.resume()
    }

    private func compareVersions'''

updated, count = pattern.subn(replacement, source, count=1)
if count != 1:
    raise SystemExit("Could not locate checkUpdates block")
source_path.write_text(updated)

Path("VERSION").write_text("1.4.3\n")

sections = {
    Path("README_RU.md"): """## Обновления из приложения

При наличии новой версии окно обновления предлагает скачать `.pkg` прямо из GitHub Release. После загрузки пакет открывается в стандартном установщике macOS. Пока пакет не подписан Developer ID, macOS может показать дополнительное предупреждение безопасности и потребовать ручное подтверждение.

""",
    Path("README.md"): """## In-app updates

When a new version is available, the update dialog can download the `.pkg` directly from the GitHub Release. The package is then opened in the standard macOS Installer. Until packages are signed with Developer ID, macOS may show an additional security warning and require manual confirmation.

""",
}
for path, section in sections.items():
    text = path.read_text()
    heading = section.splitlines()[0]
    if heading not in text:
        marker = "## Диагностика" if path.name.endswith("RU.md") else "## Diagnostics"
        text = text.replace(marker, section + marker, 1) if marker in text else text + "\n" + section
        path.write_text(text)

for temporary in [
    Path(".github/workflows/implement-update-installer.yml"),
    Path(".github/workflows/apply-in-app-update.yml"),
    Path("scripts/apply-in-app-update.py"),
]:
    if temporary.exists():
        temporary.unlink()
