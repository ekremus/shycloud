import Foundation

/// What the menu shows. `until` is the next scheduled change, nil when not scheduled.
public enum SyncStatus: Equatable, Sendable {
    case syncing(until: Date?)
    case paused(until: Date?)
    case helperDisabled
    /// Would pause, but the safety helper's watchdog hasn't run recently (fresh install or after sleep).
    case waitingForHelper

    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
}

/// State of the safety helper (the watchdog LaunchAgent) as the app sees it.
public enum SafetyHelperState: Sendable {
    /// Registered and the watchdog ran recently.
    case working
    /// Registered, but the watchdog's last-run stamp is stale or missing (it will run shortly).
    case starting
    /// Not registered/enabled.
    case disabled
}
