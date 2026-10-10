import Foundation
import ShyCloudCore

/// All user-visible status/mode strings, localized.
enum StatusText {
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func time(_ clock: ClockTime) -> String {
        let date = Calendar.current.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: Date()) ?? Date()
        return time(date)
    }

    static func line(_ status: SyncStatus) -> String {
        switch status {
        case .syncing(nil):
            String(localized: "ShyCloud — Syncing")
        case .syncing(let until?):
            String(localized: "ShyCloud — Syncing · pauses at \(time(until))")
        case .paused(nil):
            String(localized: "ShyCloud — Paused")
        case .paused(let until?):
            String(localized: "ShyCloud — Paused · syncs at \(time(until))")
        case .catchingUp(let until):
            String(localized: "ShyCloud — Catching up · pauses at \(time(until))")
        case .helperDisabled:
            String(localized: "Safety helper disabled — not pausing")
        }
    }

    static func lastSynced(_ date: Date) -> String {
        String(localized: "Last synced: \(date.formatted(date: .abbreviated, time: .shortened))")
    }

    static func title(for mode: SyncMode, schedule: Schedule) -> String {
        switch mode {
        case .alwaysSync:
            String(localized: "Sync On")
        case .alwaysPause:
            String(localized: "Sync Off")
        case .scheduled:
            String(localized: "Scheduled (\(time(schedule.start))–\(time(schedule.end)))")
        }
    }
}
