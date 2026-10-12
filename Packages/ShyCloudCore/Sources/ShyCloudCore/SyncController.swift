import Foundation
import Observation
import os

/// Decides whether sync should run and applies it idempotently (spec §2, §4, §5).
/// Pausing is a deep pause: targets are frozen but breathe (`Breather`), thaw while apps launch,
/// and a health check backs off for `cooldownDuration` if iCloud stops answering.
/// With `AppSettings.stopUploadsCompletely` targets are held without breathing (full stop) and the
/// health check is skipped, because apps waiting on iCloud are expected in that mode.
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

    /// A new `bird` usually starts a few seconds after the old one exits; re-apply at these delays after an exit.
    public static let exitFollowUpDelays: [TimeInterval] = [2, 5, 10]

    private static let logger = Logger(subsystem: "com.ekremus.ShyCloud", category: "Sync")

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
    @ObservationIgnored private let followUpTimer: any OneShotTimer
    /// How the paused targets are held right now; nil while nothing is held.
    @ObservationIgnored private var hold: Hold?
    /// Last logged value of `stopUploadsCompletely`, so the log shows every change.
    @ObservationIgnored private var loggedStopUploads: Bool?
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
        followUpTimer = makeTimer(0.5)
    }

    /// Launch sequence, spec §5.1.
    public func start(registerHelper: () -> Void) {
        writeHeartbeat()
        processes.resumeAll()
        registerHelper()
        processes.onPausedProcessExit = { [weak self] in self?.pausedProcessExited() }
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
        if isPausedNow { Self.logger.notice("launch thaw started") }
        if isPausedNow { apply() }
    }

    private func pausedProcessExited() {
        Self.logger.notice("paused process exited")
        apply()
        scheduleExitFollowUp(step: 0)
    }

    private func scheduleExitFollowUp(step: Int) {
        let delays = Self.exitFollowUpDelays
        guard step < delays.count, !isAsleep, !isTerminating else { return }
        let wait = delays[step] - (step > 0 ? delays[step - 1] : 0)
        followUpTimer.schedule(after: wait) { [weak self] in
            self?.apply()
            self?.scheduleExitFollowUp(step: step + 1)
        }
    }

    public func handleWake() {
        isAsleep = false
        writeHeartbeat()
        apply()
    }

    public func handleWillSleep() {
        isAsleep = true
        endThawSilently()
        followUpTimer.cancel()
        probeTimer.cancel() // needed: a wake within the timeout would otherwise let it fire although targets ran during sleep
        resumeEverything(reason: "sleep")
        runningSince = nil
        status = .syncing(until: nil)
        activity.setHolding(false)
    }

    public func handlePowerOff() {
        powerOffAt = now()
        followUpTimer.cancel()
        resumeEverything(reason: "power-off")
        status = .syncing(until: nil)
        activity.setHolding(false)
    }

    /// Every termination path: resume everything and never pause again in this process.
    public func prepareToQuit() {
        isTerminating = true
        endThawSilently()
        followUpTimer.cancel()
        resumeEverything(reason: "quit")
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
        if loggedStopUploads != settings.stopUploadsCompletely {
            loggedStopUploads = settings.stopUploadsCompletely
            Self.logger.notice("stop uploads completely: \(self.settings.stopUploadsCompletely ? "on" : "off", privacy: .public)")
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
                resumeEverything(reason: "cooldown")
                if runningSince == nil { runningSince = date }
                let pausesAgainFirst = nextChange.map { cooldownEnd < $0 } ?? true
                status = .syncing(until: pausesAgainFirst ? cooldownEnd : nil)
                activity.setHolding(false)
                return
            }
            if isThawing {
                // An app is launching; the status stays "paused" for these few seconds.
                resumeEverything(reason: "launch thaw")
            } else {
                holdTargets()
            }
            runningSince = nil
            status = .paused(until: nextChange)
            activity.setHolding(true)
            return
        }

        let reason: String
        if wantsRunning {
            reason = settings.mode == .scheduled ? "window" : "mode"
        } else {
            reason = isHeartbeatWritten ? "helper" : "heartbeat"
        }
        resumeEverything(reason: reason)
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

    /// Stops the enabled targets and resumes the others. Breathing unless `stopUploadsCompletely`.
    private func holdTargets() {
        let enabled = settings.enabledTargets
        let wanted: Hold = settings.stopUploadsCompletely ? .fullStop : .breathing
        processes.resume(PauseTarget.allCases.filter { !enabled.contains($0) })
        switch wanted {
        case .breathing:
            // During a release window the breather re-stops at its end; pausing now would cut the breath short.
            if !breather.isReleased { processes.pause(enabled) }
            breather.start()
        case .fullStop:
            // Stop the breather first: a target released for a breath is stopped again by `pause`.
            breather.stop()
            processes.pause(enabled)
        }
        if hold == nil {
            Self.logger.notice("pause started: \(wanted.rawValue, privacy: .public)")
        } else if hold != wanted {
            Self.logger.notice("pause switched to \(wanted.rawValue, privacy: .public)")
        }
        hold = wanted
    }

    /// Stopped targets are only ever left held (breathing or full stop); this is the one way out.
    private func resumeEverything(reason: String) {
        if hold != nil { Self.logger.notice("resumed: \(reason, privacy: .public)") }
        hold = nil
        breather.stop()
        processes.resumeAll()
    }

    private func endThaw() {
        guard isThawing else { return }
        isThawing = false
        Self.logger.notice("launch thaw ended")
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
        Self.logger.notice("cooldown ended")
        return nil
    }

    /// Health check (spec §4): only while targets are frozen and breathing, one call at a time.
    /// Never in full stop (`stopUploadsCompletely`): there the call is expected to hang until the next
    /// launch thaw, and a timeout must not start a cooldown that would let uploads run.
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
        Self.logger.notice("probe timeout: cooldown started")
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

/// How paused targets are held (spec §4.1).
private enum Hold: String {
    /// Stopped, released for `Breather.breathDuration` every `Breather.breathInterval`.
    case breathing
    /// Stopped until a launch thaw or resume (`AppSettings.stopUploadsCompletely`).
    case fullStop = "full stop"
}
