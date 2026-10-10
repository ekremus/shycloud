/// A wall-clock time of day (hour 0–23, minute 0–59).
public struct ClockTime: Codable, Hashable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        precondition((0..<24).contains(hour) && (0..<60).contains(minute), "Invalid clock time \(hour):\(minute)")
        self.hour = hour
        self.minute = minute
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }
}
