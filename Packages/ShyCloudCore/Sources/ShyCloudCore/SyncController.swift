import Foundation
import Observation

/// Decides whether sync should run and applies it idempotently (spec §2, §4, §5).
@MainActor
@Observable
public final class SyncController {
    public static let syncCreditDuration: TimeInterval = 20 * 60
    public static let catchUpDuration: TimeInterval = 30 * 60
    public static let staleSyncThreshold: TimeInterval = 24 * 3600

    public private(set) var status: SyncStatus = .syncing(until: nil)
    public var isPausedNow: Bool { status.isPaused }

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let processes: any ProcessControlling
    @ObservationIgnored private let files: SafetyFiles
    @ObservationIgnored private let activity: any ActivityHolding
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let calendar: @MainActor () -> Calendar
    @ObservationIgnored private let isHelperEnabled: @MainActor () -> Bool
    @ObservationIgnored private var runningSince: Date?
    @ObservationIgnored private var catchUpUntil: Date?
    /// Between willSleep and didWake nothing may re-pause (a late tick could fire).
    @ObservationIgnored private var isAsleep = false

    public init(
        settings: AppSettings,
        processes: any ProcessControlling,
        files: SafetyFiles,
        activity: any ActivityHolding,
        now: @escaping @MainActor () -> Date = { Date() },
        calendar: @escaping @MainActor () -> Calendar = { Calendar.current },
        isHelperEnabled: @escaping @MainActor () -> Bool
    ) {
        self.settings = settings
        self.processes = processes
        self.files = files
        self.activity = activity
        self.now = now
        self.calendar = calendar
        self.isHelperEnabled = isHelperEnabled
    }

    /// Launch sequence, spec §5.1.
    public func start(registerHelper: () -> Void) {
        files.deleteKeepPaused()
        try? files.writeHeartbeat(now())
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
        try? files.writeHeartbeat(now())
        apply()
    }

    public func handleWake() {
        isAsleep = false
        try? files.writeHeartbeat(now())
        considerCatchUp()
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
        processes.resumeAll()
        activity.setHolding(false)
    }

    /// Quit menu path. `keepPaused` only matters when currently paused.
    public func prepareToQuit(keepPaused: Bool) {
        if keepPaused, isPausedNow {
            try? files.writeKeepPaused(processes.pausedProcesses())
        } else {
            processes.resumeAll()
        }
        activity.setHolding(false)
    }

    public func apply() {
        guard !isAsleep else { return }
        let date = now()
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
            ? [schedule.nextChange(after: date, calendar: cal), catchUpUntil].compactMap { $0 }.min()
            : nil

        if !wantsRunning, isHelperEnabled() {
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
            status = .helperDisabled
        } else if settings.mode == .scheduled, !insideWindow, let until = catchUpUntil {
            status = .catchingUp(until: until)
        } else {
            status = .syncing(until: nextChange)
        }
        activity.setHolding(false)
    }

    private func considerCatchUp() {
        guard settings.mode == .scheduled, catchUpUntil == nil else { return }
        let date = now()
        guard !settings.schedule.isInside(date, calendar: calendar()) else { return }
        let last = settings.lastSyncedAt ?? .distantPast
        if date.timeIntervalSince(last) > Self.staleSyncThreshold {
            catchUpUntil = date.addingTimeInterval(Self.catchUpDuration)
        }
    }
}
