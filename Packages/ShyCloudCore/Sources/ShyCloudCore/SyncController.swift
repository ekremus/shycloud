import Foundation
import Observation

/// Decides whether sync should run and applies it idempotently (spec §2, §4, §5).
@MainActor
@Observable
public final class SyncController {
    public static let syncCreditDuration: TimeInterval = 20 * 60
    public static let catchUpDuration: TimeInterval = 30 * 60
    public static let staleSyncThreshold: TimeInterval = 24 * 3600
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
    @ObservationIgnored private var catchUpUntil: Date?
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
            // iCloud ran normally before ShyCloud existed; don't force a catch-up on first launch.
            settings.lastSyncedAt = now()
        }
        considerCatchUp()
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
        considerCatchUp()
        apply()
    }

    public func handleWillSleep() {
        isAsleep = true
        processes.resumeAll()
        runningSince = nil
        catchUpUntil = nil // sleep cuts a catch-up short; the next wake decides afresh
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
        // Credit a completed sync before the catch-up can expire on this same tick.
        if let since = runningSince, date.timeIntervalSince(since) >= Self.syncCreditDuration {
            settings.lastSyncedAt = date
        }
        if let until = catchUpUntil, date >= until { catchUpUntil = nil }

        let insideWindow = schedule.isInside(date, calendar: cal)
        let wantsRunning: Bool
        switch settings.mode {
        case .alwaysSync: wantsRunning = true
        case .alwaysPause: wantsRunning = false
        case .scheduled: wantsRunning = insideWindow || catchUpUntil != nil
        }
        let nextChange: Date? = settings.mode == .scheduled
            ? scheduledNextChange(at: date, insideWindow: insideWindow, calendar: cal)
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
        } else if settings.mode == .scheduled, !insideWindow, catchUpUntil != nil, let nextChange {
            status = .catchingUp(until: nextChange)
        } else {
            status = .syncing(until: nextChange)
        }
        activity.setHolding(false)
    }

    /// When the running/paused state will next flip. Inside the window that is the window's end;
    /// a catch-up that runs into the window lasts until the window closes.
    private func scheduledNextChange(at date: Date, insideWindow: Bool, calendar cal: Calendar) -> Date {
        let schedule = settings.schedule
        let windowChange = schedule.nextChange(after: date, calendar: cal)
        guard !insideWindow, let until = catchUpUntil else { return windowChange }
        guard windowChange <= until else { return until }
        let windowEnd = schedule.nextChange(after: windowChange, calendar: cal)
        return max(until, windowEnd)
    }

    private func writeHeartbeat() {
        do {
            try files.writeHeartbeat(now())
            isHeartbeatWritten = true
        } catch {
            isHeartbeatWritten = false
        }
    }

    private func considerCatchUp() {
        let date = now()
        if let until = catchUpUntil, date >= until { catchUpUntil = nil }
        guard settings.mode == .scheduled, catchUpUntil == nil else { return }
        guard !settings.schedule.isInside(date, calendar: calendar()) else { return }
        let last = settings.lastSyncedAt ?? .distantPast
        if date.timeIntervalSince(last) > Self.staleSyncThreshold {
            catchUpUntil = date.addingTimeInterval(Self.catchUpDuration)
        }
    }
}
