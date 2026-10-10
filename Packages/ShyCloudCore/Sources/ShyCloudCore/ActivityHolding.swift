import Foundation

/// Keeps App Nap from delaying the heartbeat while anything is paused.
@MainActor
public protocol ActivityHolding: AnyObject {
    func setHolding(_ holding: Bool)
}

@MainActor
public final class ProcessActivityHolder: ActivityHolding {
    private var token: (any NSObjectProtocol)?

    public init() {}

    public func setHolding(_ holding: Bool) {
        if holding, token == nil {
            token = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Keeping iCloud sync paused safely"
            )
        } else if !holding, let token {
            ProcessInfo.processInfo.endActivity(token)
            self.token = nil
        }
    }
}
