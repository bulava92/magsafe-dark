import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

private func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    guard actual == expected else {
        throw TestFailure.failed("\(message): expected \(expected), got \(actual)")
    }
}

private func runTests() throws {
    let now = Date(timeIntervalSince1970: 1_000)

    var persistent = LEDState(persistentMode: .off)
    try expect(persistent.effectiveMode(at: now), .off, "Persistent mode")

    persistent.addOverride(kind: .timer, mode: .orange, duration: 60, now: now)
    try expect(persistent.effectiveMode(at: now.addingTimeInterval(10)), .orange, "Timer override")
    try expect(persistent.effectiveMode(at: now.addingTimeInterval(61)), .off, "Timer restoration")

    var priority = LEDState(persistentMode: .system)
    priority.addOverride(kind: .timer, mode: .off, duration: 300, now: now)
    priority.addOverride(kind: .task, mode: .orange, now: now.addingTimeInterval(1))
    try expect(priority.effectiveMode(at: now.addingTimeInterval(2)), .orange, "Newest override priority")

    priority.removeOverrides(kind: .task)
    try expect(priority.effectiveMode(at: now.addingTimeInterval(2)), .off, "Underlying timer restoration")

    var remaining = LEDState()
    remaining.addOverride(kind: .timer, mode: .off, duration: 60, now: now)
    remaining.addOverride(kind: .timer, mode: .orange, duration: 120, now: now.addingTimeInterval(1))
    try expect(remaining.timerRemainingSeconds(at: now.addingTimeInterval(2)), 119, "Latest timer remaining")

    try expect(LEDMode.system.aclcValue, 0, "System ACLC")
    try expect(LEDMode.off.aclcValue, 1, "Off ACLC")
    try expect(LEDMode.green.aclcValue, 3, "Green ACLC")
    try expect(LEDMode.orange.aclcValue, 4, "Orange ACLC")
    try expect(LEDMode.flash.aclcValue, 5, "Flash ACLC")
    try expect(LEDMode.blinkSlow.aclcValue, 6, "Slow blink ACLC")
    try expect(LEDMode.blinkFast.aclcValue, 7, "Fast blink ACLC")
    try expect(LEDMode.blinkOff.aclcValue, 19, "Blink-off ACLC")
}

do {
    try runTests()
    print("MagSafeCore tests passed")
} catch {
    fputs("MagSafeCore tests failed: \(error)\n", stderr)
    exit(1)
}
