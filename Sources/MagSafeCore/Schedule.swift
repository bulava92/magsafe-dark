import Foundation

public struct ScheduleTime: Codable, Equatable, Hashable, Sendable, Comparable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) throws {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw ScheduleValidationError.invalidTime
        }
        self.hour = hour
        self.minute = minute
    }

    public init(_ value: String) throws {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            throw ScheduleValidationError.invalidTime
        }
        try self.init(hour: hour, minute: minute)
    }

    public var minuteOfDay: Int { hour * 60 + minute }
    public var stringValue: String { String(format: "%02d:%02d", hour, minute) }

    public static func < (lhs: ScheduleTime, rhs: ScheduleTime) -> Bool {
        lhs.minuteOfDay < rhs.minuteOfDay
    }
}

public struct ScheduleRule: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var enabled: Bool
    public var days: Set<Int>
    public var start: ScheduleTime
    public var end: ScheduleTime
    public var mode: LEDMode

    public init(
        id: String = UUID().uuidString,
        enabled: Bool = true,
        days: Set<Int>,
        start: ScheduleTime,
        end: ScheduleTime,
        mode: LEDMode
    ) throws {
        guard !days.isEmpty, days.allSatisfy({ (1...7).contains($0) }) else {
            throw ScheduleValidationError.invalidWeekday
        }
        guard start != end else { throw ScheduleValidationError.zeroLengthInterval }
        self.id = id
        self.enabled = enabled
        self.days = days
        self.start = start
        self.end = end
        self.mode = mode
    }

    public var crossesMidnight: Bool { end < start }
}

public enum ScheduleFallback: String, Codable, CaseIterable, Sendable {
    case system
    case off
    case persistent

    public func mode(persistentMode: LEDMode) -> LEDMode {
        switch self {
        case .system: return .system
        case .off: return .off
        case .persistent: return persistentMode
        }
    }
}

public struct LEDSchedule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var fallback: ScheduleFallback
    public var rules: [ScheduleRule]

    public init(enabled: Bool = false, fallback: ScheduleFallback = .system, rules: [ScheduleRule] = []) {
        self.enabled = enabled
        self.fallback = fallback
        self.rules = rules
    }

    public func validate() throws {
        let activeRules = rules.filter(\.enabled)
        var occupied = Array(repeating: [Bool](repeating: false, count: 1440), count: 7)

        for rule in activeRules {
            guard !rule.days.isEmpty, rule.days.allSatisfy({ (1...7).contains($0) }) else {
                throw ScheduleValidationError.invalidWeekday
            }
            guard rule.start != rule.end else { throw ScheduleValidationError.zeroLengthInterval }

            for day in rule.days {
                for (targetDay, minute) in rule.coveredMinutes(startDay: day) {
                    let dayIndex = targetDay - 1
                    if occupied[dayIndex][minute] {
                        throw ScheduleValidationError.overlap(day: targetDay, minute: minute)
                    }
                    occupied[dayIndex][minute] = true
                }
            }
        }
    }

    public func mode(at date: Date, calendar: Calendar = .current) -> LEDMode? {
        guard enabled else { return nil }
        let weekday = Self.isoWeekday(for: date, calendar: calendar)
        let minute = Self.minuteOfDay(for: date, calendar: calendar)

        for rule in rules where rule.enabled {
            if rule.matches(weekday: weekday, minute: minute) {
                return rule.mode
            }
        }
        return nil
    }

    public func resolvedMode(at date: Date, persistentMode: LEDMode, calendar: Calendar = .current) -> LEDMode {
        mode(at: date, calendar: calendar) ?? fallback.mode(persistentMode: persistentMode)
    }

    public func nextBoundary(after date: Date, calendar: Calendar = .current) -> Date? {
        guard enabled, !rules.filter(\.enabled).isEmpty else { return nil }
        var candidates: [Date] = []

        for offset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            let isoDay = Self.isoWeekday(for: day, calendar: calendar)
            for rule in rules where rule.enabled {
                if rule.days.contains(isoDay),
                   let startDate = Self.date(on: day, time: rule.start, calendar: calendar),
                   startDate > date {
                    candidates.append(startDate)
                }

                let endDay: Date
                if rule.crossesMidnight {
                    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
                    endDay = nextDay
                } else {
                    endDay = day
                }
                if rule.days.contains(isoDay),
                   let endDate = Self.date(on: endDay, time: rule.end, calendar: calendar),
                   endDate > date {
                    candidates.append(endDate)
                }
            }
        }
        return candidates.min()
    }

    private static func isoWeekday(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    private static func minuteOfDay(for date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    private static func date(on day: Date, time: ScheduleTime, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day)
    }
}

public enum ScheduleValidationError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidTime
    case invalidWeekday
    case zeroLengthInterval
    case overlap(day: Int, minute: Int)

    public var description: String {
        switch self {
        case .invalidTime: return "Time must be in HH:mm format"
        case .invalidWeekday: return "Weekdays must be in the range 1...7"
        case .zeroLengthInterval: return "Schedule interval must not be empty"
        case let .overlap(day, minute):
            return String(format: "Schedule rules overlap on weekday %d at %02d:%02d", day, minute / 60, minute % 60)
        }
    }
}

private extension ScheduleRule {
    func matches(weekday: Int, minute: Int) -> Bool {
        if !crossesMidnight {
            return days.contains(weekday) && minute >= start.minuteOfDay && minute < end.minuteOfDay
        }
        if days.contains(weekday), minute >= start.minuteOfDay { return true }
        let previousDay = weekday == 1 ? 7 : weekday - 1
        return days.contains(previousDay) && minute < end.minuteOfDay
    }

    func coveredMinutes(startDay: Int) -> [(Int, Int)] {
        if !crossesMidnight {
            return (start.minuteOfDay..<end.minuteOfDay).map { (startDay, $0) }
        }
        let nextDay = startDay == 7 ? 1 : startDay + 1
        let first = (start.minuteOfDay..<1440).map { (startDay, $0) }
        let second = (0..<end.minuteOfDay).map { (nextDay, $0) }
        return first + second
    }
}
