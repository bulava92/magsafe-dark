import Foundation
import MagSafeCore

private struct ManualOverride: Codable {
    let mode: LEDMode
    let expiresAt: Date
}

private struct SchedulerStatus: Codable {
    let enabled: Bool
    let resolvedMode: LEDMode
    let scheduleMode: LEDMode?
    let manualOverride: ManualOverride?
    let nextBoundary: Date?
    let deferredByTemporaryState: Bool
}

private let environment = ProcessInfo.processInfo.environment
private let home = FileManager.default.homeDirectoryForCurrentUser
private let support = URL(fileURLWithPath: environment["MAGSAFE_DARK_APP_SUPPORT"] ?? home.appendingPathComponent("Library/Application Support/MagSafe Dark").path)
private let scheduleDirectory = support.appendingPathComponent("Schedule")
private let stateDirectory = support.appendingPathComponent("State")
private let scheduleURL = URL(fileURLWithPath: environment["MAGSAFE_DARK_SCHEDULE"] ?? scheduleDirectory.appendingPathComponent("schedule.json").path)
private let manualURL = scheduleDirectory.appendingPathComponent("manual-override.json")
private let persistentURL = scheduleDirectory.appendingPathComponent("persistent-mode.txt")
private let temporaryURL = stateDirectory.appendingPathComponent("temporary.state")
private let clientPath = environment["MAGSAFE_DARK_CLIENT"] ?? "/usr/local/libexec/magsafe-led-client"
private let encoder: JSONEncoder = {
    let value = JSONEncoder()
    value.outputFormatting = [.prettyPrinted, .sortedKeys]
    value.dateEncodingStrategy = .iso8601
    return value
}()
private let decoder: JSONDecoder = {
    let value = JSONDecoder()
    value.dateDecodingStrategy = .iso8601
    return value
}()

private func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

private func ensureDirectories() throws {
    try FileManager.default.createDirectory(at: scheduleDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
}

private func defaultSchedule() throws -> LEDSchedule {
    let allDays = Set(1...7)
    return LEDSchedule(
        enabled: false,
        fallback: .system,
        rules: [
            try ScheduleRule(id: "day", days: allDays, start: ScheduleTime("08:00"), end: ScheduleTime("23:00"), mode: .system),
            try ScheduleRule(id: "night", days: allDays, start: ScheduleTime("23:00"), end: ScheduleTime("08:00"), mode: .off)
        ]
    )
}

private func loadSchedule(createIfMissing: Bool = true) throws -> LEDSchedule {
    try ensureDirectories()
    if !FileManager.default.fileExists(atPath: scheduleURL.path) {
        guard createIfMissing else { return LEDSchedule() }
        let value = try defaultSchedule()
        try encoder.encode(value).write(to: scheduleURL, options: .atomic)
        return value
    }
    let value = try decoder.decode(LEDSchedule.self, from: Data(contentsOf: scheduleURL))
    try value.validate()
    return value
}

private func saveSchedule(_ schedule: LEDSchedule) throws {
    try schedule.validate()
    try ensureDirectories()
    try encoder.encode(schedule).write(to: scheduleURL, options: .atomic)
}

private func persistentMode() -> LEDMode {
    guard let text = try? String(contentsOf: persistentURL).trimmingCharacters(in: .whitespacesAndNewlines),
          let mode = LEDMode(rawValue: text) else { return .system }
    return mode
}

private func savePersistentMode(_ mode: LEDMode) throws {
    try ensureDirectories()
    try (mode.rawValue + "\n").write(to: persistentURL, atomically: true, encoding: .utf8)
}

private func activeManualOverride(now: Date = Date()) -> ManualOverride? {
    guard let data = try? Data(contentsOf: manualURL),
          let value = try? decoder.decode(ManualOverride.self, from: data) else { return nil }
    if value.expiresAt <= now {
        try? FileManager.default.removeItem(at: manualURL)
        return nil
    }
    return value
}

private func temporaryStateIsActive(now: Date = Date()) -> Bool {
    guard let text = try? String(contentsOf: temporaryURL) else { return false }
    let fields = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t", omittingEmptySubsequences: false)
    guard fields.count >= 2, let end = TimeInterval(fields[1]) else { return false }
    return end == 0 || end > now.timeIntervalSince1970
}

@discardableResult
private func runClient(_ mode: LEDMode) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: clientPath)
    process.arguments = [mode.rawValue]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            FileHandle.standardError.write(data)
        }
        return process.terminationStatus
    } catch {
        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
        return 126
    }
}

private func resolveStatus(now: Date = Date()) throws -> SchedulerStatus {
    let schedule = try loadSchedule()
    let persistent = persistentMode()
    let manual = activeManualOverride(now: now)
    let scheduleMode = schedule.mode(at: now)
    let mode = manual?.mode ?? (schedule.enabled ? schedule.resolvedMode(at: now, persistentMode: persistent) : persistent)
    return SchedulerStatus(
        enabled: schedule.enabled,
        resolvedMode: mode,
        scheduleMode: scheduleMode,
        manualOverride: manual,
        nextBoundary: schedule.nextBoundary(after: now),
        deferredByTemporaryState: temporaryStateIsActive(now: now)
    )
}

@discardableResult
private func apply(now: Date = Date(), force: Bool = false) throws -> Int32 {
    let status = try resolveStatus(now: now)
    if status.deferredByTemporaryState { return 0 }
    return runClient(status.resolvedMode)
}

private func installManualOverride(_ mode: LEDMode, now: Date = Date()) throws {
    var schedule = try loadSchedule()
    try savePersistentMode(mode)
    guard schedule.enabled, let boundary = schedule.nextBoundary(after: now) else {
        try? FileManager.default.removeItem(at: manualURL)
        guard runClient(mode) == 0 else { fail("Unable to apply manual mode", code: 69) }
        return
    }
    schedule.enabled = true
    let value = ManualOverride(mode: mode, expiresAt: boundary)
    try encoder.encode(value).write(to: manualURL, options: .atomic)
    guard runClient(mode) == 0 else { fail("Unable to apply manual override", code: 69) }
}

private func setEnabled(_ enabled: Bool) throws {
    var schedule = try loadSchedule()
    schedule.enabled = enabled
    try saveSchedule(schedule)
    try? FileManager.default.removeItem(at: manualURL)
    guard try apply(force: true) == 0 else { fail("Unable to apply schedule", code: 69) }
}

private func printJSON<T: Encodable>(_ value: T) throws {
    FileHandle.standardOutput.write(try encoder.encode(value))
    print()
}

private func runLoop() throws -> Never {
    let center = NotificationCenter.default
    var shouldResolve = true
    let clockObserver = center.addObserver(forName: NSNotification.Name.NSSystemClockDidChange, object: nil, queue: nil) { _ in shouldResolve = true }
    let zoneObserver = center.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: nil) { _ in shouldResolve = true }
    defer {
        center.removeObserver(clockObserver)
        center.removeObserver(zoneObserver)
    }

    while true {
        autoreleasepool {
            if shouldResolve {
                _ = try? apply()
                shouldResolve = false
            }
        }
        let status = try resolveStatus()
        let delay: TimeInterval
        if status.deferredByTemporaryState {
            delay = 2
        } else if let boundary = status.nextBoundary {
            delay = max(1, min(boundary.timeIntervalSinceNow + 0.5, 3600))
        } else {
            delay = 3600
        }
        RunLoop.current.run(until: Date().addingTimeInterval(delay))
        shouldResolve = true
    }
}

let arguments = CommandLine.arguments
let command = arguments.count > 1 ? arguments[1] : "status"

do {
    switch command {
    case "init-default":
        let value = try defaultSchedule()
        try saveSchedule(value)
        print(scheduleURL.path)
    case "show":
        try printJSON(loadSchedule())
    case "validate":
        let value = try loadSchedule()
        try value.validate()
        print("valid")
    case "status":
        try printJSON(resolveStatus())
    case "apply":
        let force = arguments.contains("--force")
        exit(try apply(force: force))
    case "enable":
        try setEnabled(true)
    case "disable":
        try setEnabled(false)
    case "manual":
        guard arguments.count == 3, let mode = LEDMode(rawValue: arguments[2]) else {
            fail("Usage: magsafe-scheduler manual MODE", code: 64)
        }
        try installManualOverride(mode)
    case "clear-manual":
        try? FileManager.default.removeItem(at: manualURL)
        exit(try apply(force: true))
    case "persistent":
        guard arguments.count == 3, let mode = LEDMode(rawValue: arguments[2]) else {
            fail("Usage: magsafe-scheduler persistent MODE", code: 64)
        }
        try savePersistentMode(mode)
        exit(try apply(force: true))
    case "next":
        if let date = try loadSchedule().nextBoundary(after: Date()) {
            print(Int(date.timeIntervalSince1970))
        }
    case "run":
        try runLoop()
    default:
        fail("Usage: magsafe-scheduler init-default|show|validate|status|apply|enable|disable|manual MODE|clear-manual|persistent MODE|next|run", code: 64)
    }
} catch let error as ScheduleValidationError {
    fail(error.description, code: 78)
} catch {
    fail(error.localizedDescription, code: 1)
}
