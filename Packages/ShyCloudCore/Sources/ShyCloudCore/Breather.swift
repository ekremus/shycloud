import Foundation

/// Deep pause (spec §4): keeps paused targets frozen but lets them breathe — every `breathInterval`
/// they run for `breathDuration`, then are stopped again. A fully frozen `bird` hangs any app that
/// makes a synchronous call to it (e.g. `FileManager.ubiquityIdentityToken`); with breathing such
/// calls return within about 2 s while iCloud does only a small trickle of work.
@MainActor
public final class Breather {
    /// Release-to-release period.
    public static let breathInterval: TimeInterval = 2.0
    /// How long targets run in each breath.
    public static let breathDuration: TimeInterval = 0.2
    /// Small, so breaths stay short and regular.
    public static let timerLeeway: TimeInterval = 0.02

    public private(set) var isRunning = false
    /// True between a release and the matching re-stop.
    public private(set) var isReleased = false

    private let timer: any OneShotTimer
    private let release: @MainActor () -> Void
    private let restop: @MainActor () -> Void

    /// `release` resumes the paused targets, `restop` stops them again.
    public init(
        timer: any OneShotTimer,
        release: @escaping @MainActor () -> Void,
        restop: @escaping @MainActor () -> Void
    ) {
        self.timer = timer
        self.release = release
        self.restop = restop
    }

    /// Starts the cycle (first breath after `breathInterval - breathDuration`). No-op while running.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        scheduleRelease()
    }

    /// Cancels the cycle. Never re-stops: the caller decides what the targets do next.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        isReleased = false
        timer.cancel()
    }

    private func scheduleRelease() {
        timer.schedule(after: Self.breathInterval - Self.breathDuration) { [weak self] in
            self?.breatheOut()
        }
    }

    private func breatheOut() {
        guard isRunning else { return }
        isReleased = true
        release()
        timer.schedule(after: Self.breathDuration) { [weak self] in
            self?.breatheIn()
        }
    }

    private func breatheIn() {
        guard isRunning else { return }
        isReleased = false
        restop()
        scheduleRelease()
    }
}
