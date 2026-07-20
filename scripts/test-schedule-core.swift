import Foundation

func makeDate(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: value)!
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!

let allDays = Set(1...7)
let schedule = LEDSchedule(
    enabled: true,
    fallback: .system,
    rules: [
        try ScheduleRule(id: "day", days: allDays, start: ScheduleTime("08:00"), end: ScheduleTime("23:00"), mode: .system),
        try ScheduleRule(id: "night", days: allDays, start: ScheduleTime("23:00"), end: ScheduleTime("08:00"), mode: .off)
    ]
)
try schedule.validate()

precondition(schedule.mode(at: makeDate("2026-07-20 12:00"), calendar: calendar) == .system)
precondition(schedule.mode(at: makeDate("2026-07-20 23:30"), calendar: calendar) == .off)
precondition(schedule.mode(at: makeDate("2026-07-21 07:59"), calendar: calendar) == .off)
precondition(schedule.mode(at: makeDate("2026-07-21 08:00"), calendar: calendar) == .system)

let next = schedule.nextBoundary(after: makeDate("2026-07-20 22:00"), calendar: calendar)
precondition(next == makeDate("2026-07-20 23:00"))

let weekdayRule = try ScheduleRule(id: "weekday", days: Set(1...5), start: ScheduleTime("09:00"), end: ScheduleTime("18:00"), mode: .green)
let weekday = LEDSchedule(enabled: true, fallback: .off, rules: [weekdayRule])
precondition(weekday.resolvedMode(at: makeDate("2026-07-20 10:00"), persistentMode: .orange, calendar: calendar) == .green)
precondition(weekday.resolvedMode(at: makeDate("2026-07-19 10:00"), persistentMode: .orange, calendar: calendar) == .off)

let overlap = LEDSchedule(
    enabled: true,
    rules: [
        try ScheduleRule(id: "a", days: [1], start: ScheduleTime("08:00"), end: ScheduleTime("12:00"), mode: .system),
        try ScheduleRule(id: "b", days: [1], start: ScheduleTime("11:00"), end: ScheduleTime("13:00"), mode: .off)
    ]
)
do {
    try overlap.validate()
    preconditionFailure("overlap was not rejected")
} catch ScheduleValidationError.overlap {
}

print("Schedule core tests passed")
