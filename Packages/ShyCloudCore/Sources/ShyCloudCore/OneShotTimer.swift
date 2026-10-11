import Dispatch
import Foundation

/// A restartable one-shot timer on the main actor. Injected so tests drive virtual time.
@MainActor
public protocol OneShotTimer: AnyObject {
    /// Calls `action` once after `delay` seconds, replacing any pending call.
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void)
    /// Drops the pending call, if any.
    func cancel()
}

/// `DispatchSourceTimer` on the main queue. One source is reused for every schedule; `leeway`
/// lets the system coalesce wake-ups (timers only ever fire late, never early).
@MainActor
public final class DispatchOneShotTimer: OneShotTimer {
    private let leeway: DispatchTimeInterval
    private var source: (any DispatchSourceTimer)?
    private var action: (@MainActor () -> Void)?

    public init(leeway: TimeInterval) {
        self.leeway = .nanoseconds(Int(max(leeway, 0) * 1_000_000_000))
    }

    public func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        self.action = action
        let source = self.source ?? makeSource()
        source.schedule(deadline: .now() + max(delay, 0), repeating: .never, leeway: leeway)
    }

    public func cancel() {
        action = nil
        source?.schedule(deadline: .distantFuture, repeating: .never)
    }

    private func makeSource() -> any DispatchSourceTimer {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.fire() }
        }
        source.schedule(deadline: .distantFuture, repeating: .never)
        source.resume()
        self.source = source
        return source
    }

    private func fire() {
        let action = self.action
        self.action = nil
        action?()
    }

    isolated deinit {
        source?.cancel()
    }
}
