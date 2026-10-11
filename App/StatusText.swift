import Foundation
import ShyCloudCore

/// All user-visible status/mode strings, localized.
enum StatusText {
    /// Template image in Assets.xcassets for the status: plain cloud while syncing, pause bars on a scheduled
    /// pause, crossed-out cloud while sync is off until the user turns it back on.
    static func iconName(_ status: SyncStatus) -> String {
        switch status {
        case .paused(nil): "MenuBarStop"
        case .paused: "MenuBarPause"
        case .syncing, .waitingForHelper, .helperDisabled: "MenuBarOnline"
        }
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func time(_ clock: ClockTime) -> String {
        let date = Calendar.current.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: Date()) ?? Date()
        return time(date)
    }

    static func line(_ status: SyncStatus) -> String {
        switch status {
        case .syncing(nil), .waitingForHelper:
            // The safety helper is invisible in the UI: while it starts, iCloud is syncing.
            String(localized: "shyCloud — Syncing")
        case .syncing(let until?):
            String(localized: "shyCloud — Syncing · pauses at \(time(until))")
        case .paused(nil):
            String(localized: "shyCloud — Paused")
        case .paused(let until?):
            String(localized: "shyCloud — Paused · syncs at \(time(until))")
        case .helperDisabled:
            String(localized: "shyCloud — Can't pause: allow shyCloud in Login Items")
        }
    }

    /// Settings header title: the live iCloud Drive state.
    static func settingsHeadline(_ status: SyncStatus) -> String {
        switch status {
        case .paused:
            String(localized: "iCloud Drive is paused")
        case .syncing, .waitingForHelper:
            String(localized: "iCloud Drive is syncing")
        case .helperDisabled:
            String(localized: "iCloud Drive can't be paused")
        }
    }

    /// Settings header subtitle: when the current state ends, or what to do.
    static func settingsDetail(_ status: SyncStatus) -> String {
        switch status {
        case .paused(let until?):
            String(localized: "Syncs at \(time(until))")
        case .paused(nil):
            String(localized: "Until you choose Sync On or Scheduled")
        case .syncing(let until?):
            String(localized: "Pauses at \(time(until))")
        case .syncing(nil), .waitingForHelper:
            String(localized: "Sync is on")
        case .helperDisabled:
            String(localized: "Allow shyCloud in System Settings › Login Items")
        }
    }

    /// "Today 08:59", "Yesterday 02:30", or a medium date for older syncs.
    private static let lastSyncedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    static func lastSynced(_ date: Date) -> String {
        String(localized: "Last synced: \(lastSyncedFormatter.string(from: date))")
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
