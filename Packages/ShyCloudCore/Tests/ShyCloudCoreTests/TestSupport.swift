import Foundation
import Testing
@testable import ShyCloudCore

enum TestTime {
    static let london = TimeZone(identifier: "Europe/London")!
    static let newYork = TimeZone(identifier: "America/New_York")!

    static func calendar(_ zone: TimeZone = london) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// "2026-10-12 14:00" in the given zone.
    static func date(_ text: String, _ zone: TimeZone = london) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }
}

@Test func packageBuilds() {
    #expect(ShyCloudCore.version == "1.0.0")
}

/// Virtual time for timer-driven code: `advance(by:)` fires due timers in deadline order.
@MainActor
final class FakeClock {
    var now: Date
    private var timers: [FakeTimer] = []

    init(_ now: Date) {
        self.now = now
    }

    func makeTimer(leeway: TimeInterval) -> FakeTimer {
        let timer = FakeTimer(clock: self, leeway: leeway)
        timers.append(timer)
        return timer
    }

    /// Deadline of the pending timer created with `leeway` (unique per use in SyncController).
    func deadline(leeway: TimeInterval) -> Date? {
        timers.first { $0.leeway == leeway }?.deadline
    }

    func advance(by seconds: TimeInterval) {
        let end = now.addingTimeInterval(seconds)
        while let next = timers
            .filter({ ($0.deadline ?? .distantFuture) <= end })
            .min(by: { $0.deadline! < $1.deadline! }) {
            now = next.deadline!
            next.fire()
        }
        now = end
    }
}

@MainActor
final class FakeTimer: OneShotTimer {
    unowned let clock: FakeClock
    let leeway: TimeInterval
    private(set) var deadline: Date?
    private var action: (@MainActor () -> Void)?

    init(clock: FakeClock, leeway: TimeInterval) {
        self.clock = clock
        self.leeway = leeway
    }

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        deadline = clock.now.addingTimeInterval(delay)
        self.action = action
    }

    func cancel() {
        deadline = nil
        action = nil
    }

    func fire() {
        let action = self.action
        cancel()
        action?()
    }
}
