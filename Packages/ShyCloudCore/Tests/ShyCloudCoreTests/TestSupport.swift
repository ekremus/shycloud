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
