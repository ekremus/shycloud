import Foundation

public enum WatchdogAction: Equatable, Sendable {
    case exit
    case resume
}

/// Pure decision logic for the watchdog LaunchAgent (spec §4, §5.5).
public enum WatchdogDecision {
    public static let staleAfter: TimeInterval = 120
    /// A heartbeat further in the future than this is treated as corrupt (stale).
    public static let futureTolerance: TimeInterval = 60
    /// The watchdog runs every 60 s; two missed runs plus slack means it is not running.
    public static let watchdogAliveWithin: TimeInterval = 180

    /// `SMAppService.status == .enabled` can be stale; the watchdog's own last run is the real proof (spec §5.5/5.7).
    public static func isWatchdogAlive(lastRun: Date?, now: Date) -> Bool {
        guard let lastRun else { return false }
        let age = now.timeIntervalSince(lastRun)
        return -futureTolerance <= age && age <= watchdogAliveWithin
    }

    public static func decide(
        heartbeat: Date?,
        now: Date,
        keepPaused: [ProcessIdentity]?,
        isAliveAndStopped: (ProcessIdentity) -> Bool
    ) -> WatchdogAction {
        if let heartbeat {
            let age = now.timeIntervalSince(heartbeat)
            if -futureTolerance <= age && age <= staleAfter { return .exit }
        }
        if let keepPaused, !keepPaused.isEmpty, keepPaused.allSatisfy(isAliveAndStopped) {
            return .exit
        }
        return .resume
    }
}
