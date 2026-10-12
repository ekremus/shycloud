import AppKit
import ShyCloudCore

/// Wires system notifications to SyncController (spec §4).
@MainActor
enum SystemEvents {
    static func observe(_ sync: SyncController) {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { sync.handleWake() }
        }
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { sync.handleWillSleep() }
        }
        workspace.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { sync.handlePowerOff() }
        }
        // Launch thaw: apps that talk to iCloud at launch must never meet a frozen bird.
        for name in [NSWorkspace.willLaunchApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { sync.handleAppLaunch() }
            }
        }
        // Activation thaw: only Finder coming to the front thaws iCloud (other apps would leak uploads in full stop).
        // SyncController ignores every other app, thaws at most once a minute, and only while paused.
        workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            let key = app.bundleIdentifier ?? "pid \(app.processIdentifier)"
            MainActor.assumeIsolated { sync.handleAppActivation(bundleID: key) }
        }
        let center = NotificationCenter.default
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { sync.apply() }
            }
        }
    }
}
