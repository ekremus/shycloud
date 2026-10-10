import Foundation

public enum WatchdogAction: Equatable, Sendable {
    case exit
    case resume
}

/// Pure decision logic for the watchdog LaunchAgent (spec §4, §5.5).
public enum WatchdogDecision {
    public static let staleAfter: TimeInterval = 120

    public static func decide(
        heartbeat: Date?,
        now: Date,
        keepPaused: [ProcessIdentity]?,
        isAliveAndStopped: (ProcessIdentity) -> Bool
    ) -> WatchdogAction {
        if let heartbeat, now.timeIntervalSince(heartbeat) <= staleAfter {
            return .exit
        }
        if let keepPaused, !keepPaused.isEmpty, keepPaused.allSatisfy(isAliveAndStopped) {
            return .exit
        }
        return .resume
    }
}
