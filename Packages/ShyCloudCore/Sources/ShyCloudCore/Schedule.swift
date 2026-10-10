import Foundation

/// A daily window in which sync is allowed to run. `end` before `start` crosses midnight.
public struct Schedule: Codable, Hashable, Sendable {
    public let start: ClockTime
    public let end: ClockTime

    public init(start: ClockTime, end: ClockTime) {
        self.start = start
        self.end = end
    }

    public static let `default` = Schedule(start: ClockTime(hour: 2, minute: 0), end: ClockTime(hour: 9, minute: 0))

    public var isValid: Bool { start != end }

    /// Start is inclusive, end is exclusive. Compares wall-clock minutes in `calendar`'s time zone.
    public func isInside(_ date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let from = start.minutesSinceMidnight
        let to = end.minutesSinceMidnight
        return from < to ? (now >= from && now < to) : (now >= from || now < to)
    }

    /// The next moment the window opens (when outside) or closes (when inside).
    public func nextChange(after date: Date, calendar: Calendar) -> Date {
        let target = isInside(date, calendar: calendar) ? end : start
        let components = DateComponents(hour: target.hour, minute: target.minute, second: 0)
        return calendar.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? date.addingTimeInterval(24 * 3600)
    }
}
