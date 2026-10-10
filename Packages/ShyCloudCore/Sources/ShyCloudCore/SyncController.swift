import Foundation
import Observation

/// Decides whether sync should run and applies it idempotently (spec §2, §4, §5).
@MainActor
@Observable
public final class SyncController {
    public static let syncCreditDuration: TimeInterval = 20 * 60
    /// After power-off nothing re-pauses for this long; if we are still running then, the logout was cancelled.
    public static let powerOffHold: TimeInterval = 60

    public private(set) var status: SyncStatus = .syncing(until: nil)
    public var isPausedNow: Bool { status.isPaused }

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let processes: any ProcessControlling
    @ObservationIgnored private let files: SafetyFiles
    @ObservationIgnored private let activity: any ActivityHolding
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let calendar: @MainActor () -> Calendar
    @ObservationIgnored private let helperState: @MainActor () -> SafetyHelperState
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
    }

    /// Launch sequence, spec §5.1.
    public func start(registerHelper: () -> Void) {
        files.deleteKeepPaused()
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

    /// Every 30 s: heartbeat + re-apply (also re-pauses a respawned process).
    public func tick() {
        writeHeartbeat()
        apply()
    }

    public func handleWake() {
        isAsleep = false
        writeHeartbeat()
        apply()
    }

    public func handleWillSleep() {
        isAsleep = true
        processes.resumeAll()
        runningSince = nil
        status = .syncing(until: nil)
        activity.setHolding(false)
    }

    public func handlePowerOff() {
        powerOffAt = now()
        processes.resumeAll()
        status = .syncing(until: nil)
        activity.setHolding(false)
    }

    /// Quit menu path. `keepPaused` only matters when currently paused.
    public func prepareToQuit(keepPaused: Bool) {
        apply() // decide on fresh state; must run before the latch below
        isTerminating = true
        var keptPaused = false
        if keepPaused, isPausedNow {
            keptPaused = (try? files.writeKeepPaused(processes.pausedProcesses())) != nil
        }
        if !keptPaused {
            // Never leave targets paused without a keep-paused record.
            processes.resumeAll()
            status = .syncing(until: nil)
        }
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
            let enabled = settings.enabledTargets
            processes.resume(PauseTarget.allCases.filter { !enabled.contains($0) })
            processes.pause(enabled)
            runningSince = nil
            status = .paused(until: nextChange)
            activity.setHolding(true)
            return
        }

        processes.resumeAll()
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

    private func writeHeartbeat() {
        do {
            try files.writeHeartbeat(now())
            isHeartbeatWritten = true
        } catch {
            isHeartbeatWritten = false
        }
    }
}
