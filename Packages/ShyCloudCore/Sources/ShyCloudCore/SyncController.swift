import Foundation
import Observation

/// Decides whether sync should run and applies it idempotently (spec §2, §4, §5).
/// Pausing is a deep pause: targets are frozen but breathe (`Breather`), thaw while apps launch,
/// and a health check backs off for `cooldownDuration` if iCloud stops answering.
@MainActor
@Observable
public final class SyncController {
    public static let syncCreditDuration: TimeInterval = 20 * 60
    /// After power-off nothing re-pauses for this long; if we are still running then, the logout was cancelled.
    public static let powerOffHold: TimeInterval = 60
    /// Targets run this long after an app launches (extended by further launches).
    public static let launchThawDuration: TimeInterval = 10
    /// A probe unanswered this long means apps are hanging on iCloud. Must exceed `Breather.breathInterval`.
    public static let probeTimeout: TimeInterval = 3.0
    /// After a probe timeout nothing is paused for this long.
    public static let cooldownDuration: TimeInterval = 10 * 60

    public private(set) var status: SyncStatus = .syncing(until: nil)
    public var isPausedNow: Bool { status.isPaused }

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let processes: any ProcessControlling
    @ObservationIgnored private let files: SafetyFiles
    @ObservationIgnored private let activity: any ActivityHolding
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let calendar: @MainActor () -> Calendar
    @ObservationIgnored private let helperState: @MainActor () -> SafetyHelperState
    @ObservationIgnored private let probe: any ResponsivenessProbe
    @ObservationIgnored private let breather: Breather
    @ObservationIgnored private let thawTimer: any OneShotTimer
    @ObservationIgnored private let probeTimer: any OneShotTimer
    /// An app is launching: targets run until `thawTimer` fires.
    @ObservationIgnored private var isThawing = false
    /// The underlying call has not returned yet (even if it already timed out). Never start a second one.
    @ObservationIgnored private var isProbeInFlight = false
    /// A probe timed out here; nothing pauses until `cooldownDuration` passes.
    @ObservationIgnored private var cooldownStartedAt: Date?
    @ObservationIgnored private var runningSince: Date?
    /// Between willSleep and didWake nothing may re-pause (a late tick could fire).
    @ObservationIgnored private var isAsleep = false
    /// After Quit nothing may re-pause (a late tick or exit callback could fire).
    @ObservationIgnored private var isTerminating = false
    /// Power-off/logout began here; nothing re-pauses until `powerOffHold` passes (a cancelled logout must not latch).
    @ObservationIgnored private var powerOffAt: Date?
    /// Without a fresh heartbeat the watchdog can't protect a pause, so we never pause (spec §5.7).
    @ObservationIgnored private var isHeartbeatWritten = false

    public init(
        settings: AppSettings,
        processes: any ProcessControlling,
        files: SafetyFiles,
        activity: any ActivityHolding,
        probe: any ResponsivenessProbe,
        makeTimer: @MainActor (_ leeway: TimeInterval) -> any OneShotTimer,
        now: @escaping @MainActor () -> Date = { Date() },
        calendar: @escaping @MainActor () -> Calendar = { Calendar.current },
        helperState: @escaping @MainActor () -> SafetyHelperState
    ) {
        self.settings = settings
        self.processes = processes
        self.files = files
        self.activity = activity
        self.now = now
        self.calendar = calendar
        self.helperState = helperState
        self.probe = probe
        breather = Breather(
            timer: makeTimer(Breather.timerLeeway),
            release: { [processes] in processes.releaseForBreath() },
            restop: { [processes] in processes.restopAfterBreath() }
        )
        thawTimer = makeTimer(1)
        probeTimer = makeTimer(0.25)
    }

    /// Launch sequence, spec §5.1.
    public func start(registerHelper: () -> Void) {
        writeHeartbeat()
        processes.resumeAll()
        registerHelper()
        processes.onPausedProcessExit = { [weak self] in self?.apply() }
        settings.onChange = { [weak self] in self?.apply() }
        if settings.lastSyncedAt == nil {
            // iCloud ran normally before ShyCloud existed; start the "Last synced" line from now.
            settings.lastSyncedAt = now()
        }
        apply()
    }

    /// Every 30 s: heartbeat + re-apply (also re-pauses a respawned process) + health check while paused.
    public func tick() {
        writeHeartbeat()
        apply()
        probeIfPaused()
    }

    /// An app will launch or just launched (workspace notifications): let targets run for
    /// `launchThawDuration`, extended by every further launch, so it can talk to iCloud freely.
    public func handleAppLaunch() {
        guard !isAsleep, !isTerminating else { return }
        thawTimer.schedule(after: Self.launchThawDuration) { [weak self] in self?.endThaw() }
        guard !isThawing else { return }
        isThawing = true
        if isPausedNow { apply() }
    }

    public func handleWake() {
        isAsleep = false
        writeHeartbeat()
        apply()
    }

    public func handleWillSleep() {
        isAsleep = true
        endThawSilently()
        probeTimer.cancel() // needed: a wake within the timeout would otherwise let it fire although targets ran during sleep
        resumeEverything()
        runningSince = nil
        status = .syncing(until: nil)
        activity.setHolding(false)
    }

    public func handlePowerOff() {
        powerOffAt = now()
        resumeEverything()
        status = .syncing(until: nil)
        activity.setHolding(false)
    }

    /// Every termination path: resume everything and never pause again in this process.
    public func prepareToQuit() {
        isTerminating = true
        endThawSilently()
        resumeEverything()
        status = .syncing(until: nil)
        activity.setHolding(false)
    }

    public func apply() {
        guard !isAsleep, !isTerminating else { return }
        let date = now()
        if let powerOffAt {
            let elapsed = date.timeIntervalSince(powerOffAt)
            // A clock set backwards must not stretch the hold either.
            if elapsed >= 0, elapsed < Self.powerOffHold { return }
            self.powerOffAt = nil
        }
        let cal = calendar()
        let schedule = settings.schedule
        // Credit a completed sync on this tick.
        if let since = runningSince, date.timeIntervalSince(since) >= Self.syncCreditDuration {
            settings.lastSyncedAt = date
        }

        let insideWindow = schedule.isInside(date, calendar: cal)
        let wantsRunning: Bool
        switch settings.mode {
        case .alwaysSync: wantsRunning = true
        case .alwaysPause: wantsRunning = false
        case .scheduled: wantsRunning = insideWindow
        }
        let nextChange: Date? = settings.mode == .scheduled
            ? settings.schedule.nextChange(after: date, calendar: cal)
            : nil

        let helper = helperState()
        if !wantsRunning, isHeartbeatWritten, helper == .working {
            if let cooldownEnd = cooldownEnd(at: date) {
                // iCloud stopped answering while paused: let it run, try again later.
                resumeEverything()
                if runningSince == nil { runningSince = date }
                let pausesAgainFirst = nextChange.map { cooldownEnd < $0 } ?? true
                status = .syncing(until: pausesAgainFirst ? cooldownEnd : nil)
                activity.setHolding(false)
                return
            }
            if isThawing {
                // An app is launching; the status stays "paused" for these few seconds.
                resumeEverything()
            } else {
                let enabled = settings.enabledTargets
                processes.resume(PauseTarget.allCases.filter { !enabled.contains($0) })
                // During a release window the breather re-stops at its end; pausing now would cut the breath short.
                if !breather.isReleased { processes.pause(enabled) }
                breather.start()
            }
            runningSince = nil
            status = .paused(until: nextChange)
            activity.setHolding(true)
            return
        }

        resumeEverything()
        if runningSince == nil { runningSince = date }
        if !wantsRunning {
            // Not pausing: either the helper is still starting up (or launchd skipped its runs during sleep)
            // or it is genuinely unavailable.
            status = isHeartbeatWritten && helper == .starting ? .waitingForHelper : .helperDisabled
        } else {
            status = .syncing(until: nextChange)
        }
        activity.setHolding(false)
    }

    /// Stopped targets are only ever left with the breather running; this is the one way out.
    private func resumeEverything() {
        breather.stop()
        processes.resumeAll()
    }

    private func endThaw() {
        guard isThawing else { return }
        isThawing = false
        if isPausedNow { apply() }
    }

    private func endThawSilently() {
        isThawing = false
        thawTimer.cancel()
    }

    /// When the current cooldown ends, or nil when not cooling down. A clock set backwards ends it.
    private func cooldownEnd(at date: Date) -> Date? {
        guard let start = cooldownStartedAt else { return nil }
        let elapsed = date.timeIntervalSince(start)
        if elapsed >= 0, elapsed < Self.cooldownDuration {
            return start.addingTimeInterval(Self.cooldownDuration)
        }
        cooldownStartedAt = nil
        return nil
    }

    /// Health check (spec §4): only while targets are frozen and breathing, one call at a time.
    private func probeIfPaused() {
        guard breather.isRunning, !isProbeInFlight else { return }
        isProbeInFlight = true
        probeTimer.schedule(after: Self.probeTimeout) { [weak self] in self?.probeTimedOut() }
        probe.ping { [weak self] in self?.probeAnswered() }
    }

    private func probeAnswered() {
        isProbeInFlight = false
        probeTimer.cancel()
    }

    private func probeTimedOut() {
        // Only a hang while the targets are really held (frozen and breathing) says iCloud stopped answering.
        guard isProbeInFlight, breather.isRunning, !isThawing, !isAsleep, !isTerminating else { return }
        cooldownStartedAt = now()
        apply()
    }

    private func writeHeartbeat() {
        do {
            try files.writeHeartbeat(now())
            isHeartbeatWritten = true
        } catch {
            isHeartbeatWritten = false
        }
    }
}
