import Foundation

public enum LEDMode: String, Codable, CaseIterable, Sendable {
    case system
    case off
    case green
    case orange
    case flash
    case blinkSlow = "blink-slow"
    case blinkFast = "blink-fast"
    case blinkOff = "blink-off"

    public var aclcValue: UInt8 {
        switch self {
        case .system: return 0
        case .off: return 1
        case .green: return 3
        case .orange: return 4
        case .flash: return 5
        case .blinkSlow: return 6
        case .blinkFast: return 7
        case .blinkOff: return 19
        }
    }
}

public enum OverrideKind: String, Codable, Sendable {
    case timer
    case task
}

public struct TemporaryOverride: Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: OverrideKind
    public let mode: LEDMode
    public let createdAt: Date
    public let expiresAt: Date?

    public init(
        id: UUID = UUID(),
        kind: OverrideKind,
        mode: LEDMode,
        createdAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.mode = mode
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    public func isActive(at date: Date = Date()) -> Bool {
        guard let expiresAt else { return true }
        return expiresAt > date
    }

    public func remainingSeconds(at date: Date = Date()) -> Int? {
        guard let expiresAt else { return nil }
        return max(0, Int(ceil(expiresAt.timeIntervalSince(date))))
    }
}

public struct LEDState: Codable, Equatable, Sendable {
    public var persistentMode: LEDMode
    public var overrides: [TemporaryOverride]

    public init(persistentMode: LEDMode = .system, overrides: [TemporaryOverride] = []) {
        self.persistentMode = persistentMode
        self.overrides = overrides
    }

    public mutating func removeExpired(at date: Date = Date()) {
        overrides.removeAll { !$0.isActive(at: date) }
    }

    public func effectiveMode(at date: Date = Date()) -> LEDMode {
        overrides
            .filter { $0.isActive(at: date) }
            .max { lhs, rhs in lhs.createdAt < rhs.createdAt }?
            .mode ?? persistentMode
    }

    public mutating func setPersistentMode(_ mode: LEDMode) {
        persistentMode = mode
    }

    @discardableResult
    public mutating func addOverride(
        kind: OverrideKind,
        mode: LEDMode,
        duration: TimeInterval? = nil,
        now: Date = Date()
    ) -> UUID {
        removeExpired(at: now)
        let item = TemporaryOverride(
            kind: kind,
            mode: mode,
            createdAt: now,
            expiresAt: duration.map { now.addingTimeInterval($0) }
        )
        overrides.append(item)
        return item.id
    }

    public mutating func removeOverride(id: UUID) {
        overrides.removeAll { $0.id == id }
    }

    public mutating func removeOverrides(kind: OverrideKind) {
        overrides.removeAll { $0.kind == kind }
    }

    public func timerRemainingSeconds(at date: Date = Date()) -> Int? {
        overrides
            .filter { $0.kind == .timer && $0.isActive(at: date) }
            .max { lhs, rhs in lhs.createdAt < rhs.createdAt }?
            .remainingSeconds(at: date)
    }
}
