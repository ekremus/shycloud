import Foundation

/// What the menu shows. `until` is the next scheduled change, nil when not scheduled.
public enum SyncStatus: Equatable, Sendable {
    case syncing(until: Date?)
    case paused(until: Date?)
    case catchingUp(until: Date)
    case helperDisabled

    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
}
