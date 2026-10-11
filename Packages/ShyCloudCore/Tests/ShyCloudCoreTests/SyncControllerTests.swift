import Foundation
import Testing
@testable import ShyCloudCore

@MainActor
final class FakeProcesses: ProcessControlling {
    var onPausedProcessExit: (@MainActor () -> Void)?
    private(set) var paused: Set<PauseTarget>
    /// Paused targets running for a breath (still owned by ShyCloud).
    private(set) var released: Set<PauseTarget> = []
    /// One entry per non-empty call, e.g. "resume drive,photos,photoAnalysis,cloudKit" (pause order).
    private(set) var log: [String] = []

    init(paused: Set<PauseTarget> = []) {
        self.paused = paused
    }

    /// When set, only these targets have a running process; pausing others finds nothing.
    var alive: Set<PauseTarget>?

    func pause(_ targets: [PauseTarget]) {
        let found = alive.map { alive in targets.filter(alive.contains) } ?? targets
        paused.formUnion(found)
        record("pause", found)
    }

    func resume(_ targets: [PauseTarget]) {
        paused.subtract(targets)
        released.subtract(targets)
        record("resume", targets)
    }

    func releaseForBreath() {
        released.formUnion(paused)
        paused.removeAll()
        record("release", Array(released))
    }

    func restopAfterBreath() {
        let targets = Array(released)
        paused.formUnion(released)
        released.removeAll()
        record("restop", targets)
    }

    private func record(_ action: String, _ targets: [PauseTarget]) {
        guard !targets.isEmpty else { return }
        let names = PauseTarget.pauseOrder.filter(targets.contains).map(\.rawValue)
        log.append("\(action) \(names.joined(separator: ","))")
    }
}

@MainActor
final class FakeActivity: ActivityHolding {
    var holding = false
    func setHolding(_ holding: Bool) { self.holding = holding }
}

@MainActor
final class FakeProbe: ResponsivenessProbe {
    private(set) var pings = 0
    private var pending: [@MainActor @Sendable () -> Void] = []

    func ping(answered: @escaping @MainActor @Sendable () -> Void) {
        pings += 1
        pending.append(answered)
    }

    /// iCloud answers every outstanding ping.
    func answer() {
        let answers = pending
        pending.removeAll()
        answers.forEach { $0() }
    }
}

@MainActor
final class Harness {
    let clock: FakeClock
    var date: Date {
        get { clock.now }
        set { clock.now = newValue }
    }
    var helperState: SafetyHelperState = .working
    let settings: AppSettings
    let processes: FakeProcesses
    let activity = FakeActivity()
    let probe = FakeProbe()
    let files: SafetyFiles
    lazy var controller = SyncController(
        settings: settings,
        processes: processes,
        files: files,
        activity: activity,
        probe: probe,
        makeTimer: { [unowned self] leeway in self.clock.makeTimer(leeway: leeway) },
        now: { [unowned self] in self.date },
        calendar: { TestTime.calendar() },
        helperState: { [unowned self] in self.helperState }
    )

    /// `paused` simulates targets left stopped by a previous crash.
    init(_ text: String, paused: Set<PauseTarget> = []) {
        clock = FakeClock(TestTime.date(text))
        processes = FakeProcesses(paused: paused)
        let name = "shycloud-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        settings = AppSettings(defaults: defaults)
        files = SafetyFiles(directory: FileManager.default.temporaryDirectory.appending(path: name))
    }

    func advance(_ seconds: TimeInterval) { clock.advance(by: seconds) }

    /// Log entries recorded after `mark`.
    func log(since mark: Int) -> [String] { Array(processes.log.dropFirst(mark)) }

    func at(_ text: String) { date = TestTime.date(text) }

    /// Invariant: whenever targets are stopped, the next breath starts within `Breather.breathInterval`.
    func expectNextBreathWithinTwoSeconds(_ note: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
        guard !processes.paused.isEmpty else { return }
        let next = clock.deadline(leeway: Breather.timerLeeway)
        #expect(next != nil, "stopped targets without a pending breath \(note)", sourceLocation: sourceLocation)
        if let next {
            #expect(next <= date.addingTimeInterval(Breather.breathInterval), "breath too late \(note)", sourceLocation: sourceLocation)
        }
    }

    /// Replaces the safety directory with a regular file so every write fails.
    func breakFiles() throws {
        try? FileManager.default.removeItem(at: files.directory)
        try Data().write(to: files.directory)
    }

    func repairFiles() throws {
        try FileManager.default.removeItem(at: files.directory)
    }
}

@MainActor
struct SyncControllerTests {
    @Test func scheduledOutsideWindowPausesDrive() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        #expect(h.processes.paused == [.drive])
        #expect(h.controller.status == .paused(until: TestTime.date("2026-10-13 02:00")))
        #expect(h.controller.isPausedNow)
        #expect(h.activity.holding)
    }

    @Test func scheduledInsideWindowSyncs() {
        let h = Harness("2026-10-12 03:00")
        h.controller.start(registerHelper: {})
        #expect(h.processes.paused.isEmpty)
        #expect(h.controller.status == .syncing(until: TestTime.date("2026-10-12 09:00")))
        #expect(!h.activity.holding)
    }

    @Test func windowBoundaryFlipsOnTick() {
        let h = Harness("2026-10-12 08:59")
        h.controller.start(registerHelper: {})
        #expect(h.processes.paused.isEmpty)
        h.at("2026-10-12 09:00")
        h.controller.tick()
        #expect(h.processes.paused == [.drive])
    }

    @Test func alwaysSyncAndAlwaysPause() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.settings.mode = .alwaysSync
        #expect(h.processes.paused.isEmpty)
        #expect(h.controller.status == .syncing(until: nil))
        h.settings.mode = .alwaysPause
        #expect(h.processes.paused == [.drive])
        #expect(h.controller.status == .paused(until: nil))
    }

    @Test func optionalTargetsFollowSettings() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.settings.pauseCloudKit = true
        #expect(h.processes.paused == [.drive, .cloudKit])
        h.settings.pauseCloudKit = false
        #expect(h.processes.paused == [.drive])
    }

    @Test func helperDisabledNeverPauses() {
        let h = Harness("2026-10-12 14:00")
        h.helperState = .disabled
        h.controller.start(registerHelper: {})
        #expect(h.processes.paused.isEmpty)
        #expect(h.controller.status == .helperDisabled)
        #expect(!h.controller.isPausedNow)
    }

    @Test func helperStartingWaitsWithoutPausing() {
        let h = Harness("2026-10-12 14:00")
        h.helperState = .starting
        h.controller.start(registerHelper: {})
        #expect(h.processes.paused.isEmpty)
        #expect(h.controller.status == .waitingForHelper)
        #expect(!h.controller.isPausedNow)
        #expect(!h.activity.holding)
    }

    @Test func helperStartingThenWorkingPausesOnNextTick() {
        let h = Harness("2026-10-12 14:00")
        h.helperState = .starting
        h.controller.start(registerHelper: {})
        #expect(h.processes.paused.isEmpty)
        h.helperState = .working
        h.controller.tick()
        #expect(h.processes.paused == [.drive])
        #expect(h.controller.status.isPaused)
    }

    @Test func helperStartingWhilePausedResumesAndWaits() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        #expect(h.processes.paused == [.drive])
        h.helperState = .starting
        h.controller.tick()
        #expect(h.processes.paused.isEmpty)
        #expect(h.controller.status == .waitingForHelper)
    }

    @Test func helperStartingWhileSyncingStaysSyncing() {
        let h = Harness("2026-10-12 08:00") // inside the sync window
        h.helperState = .starting
        h.controller.start(registerHelper: {})
        #expect(h.controller.status != .waitingForHelper)
        #expect(!h.controller.status.isPaused)
    }

    @Test func launchOrderWritesHeartbeatResumesThenRegisters() {
        let h = Harness("2026-10-12 14:00", paused: Set(PauseTarget.allCases)) // previous crash
        var heartbeatWhenRegistering: Date?
        var pausedWhenRegistering: Set<PauseTarget>?
        h.controller.start(registerHelper: {
            heartbeatWhenRegistering = h.files.readHeartbeat()
            pausedWhenRegistering = h.processes.paused
        })
        #expect(heartbeatWhenRegistering == h.date)
        #expect(pausedWhenRegistering == [])
        #expect(h.processes.log.first == "resume drive,photos,photoAnalysis,cloudKit")
    }

    @Test func firstLaunchInitialisesLastSyncedAt() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        #expect(h.settings.lastSyncedAt == h.date)
        #expect(h.controller.isPausedNow)
    }

    @Test func wakeAfterMissedWindowStaysPaused() {
        let h = Harness("2026-10-12 14:00")
        h.settings.lastSyncedAt = TestTime.date("2026-10-11 09:00") // 30 h old at wake
        h.controller.start(registerHelper: {})
        h.controller.handleWillSleep()
        h.at("2026-10-13 15:00") // slept through the whole window
        h.controller.handleWake()
        #expect(h.controller.status == .paused(until: TestTime.date("2026-10-14 02:00")))
        #expect(h.processes.paused == [.drive])
    }

    @Test func syncCreditAfterTwentyMinutes() {
        let h = Harness("2026-10-12 02:00")
        h.controller.start(registerHelper: {})
        h.settings.lastSyncedAt = nil
        h.at("2026-10-12 02:19")
        h.controller.tick()
        #expect(h.settings.lastSyncedAt == nil)
        h.at("2026-10-12 02:21")
        h.controller.tick()
        #expect(h.settings.lastSyncedAt == TestTime.date("2026-10-12 02:21"))
    }

    @Test func sleepResumesAndWakeRepauses() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.handleWillSleep()
        #expect(h.processes.paused.isEmpty)
        #expect(!h.activity.holding)
        h.at("2026-10-12 14:05")
        h.controller.handleWake()
        #expect(h.processes.paused == [.drive])
    }

    @Test func tickBetweenSleepAndWakeDoesNotRepause() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.handleWillSleep()
        h.controller.tick()
        #expect(h.processes.paused.isEmpty)
    }

    @Test func wakeWritesHeartbeat() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.handleWillSleep()
        h.at("2026-10-12 16:00")
        h.controller.handleWake()
        #expect(h.files.readHeartbeat() == TestTime.date("2026-10-12 16:00"))
    }

    @Test func powerOffResumes() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.handlePowerOff()
        #expect(h.processes.paused.isEmpty)
    }

    @Test func quitAlwaysResumes() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        #expect(h.processes.paused == [.drive])
        h.controller.prepareToQuit()
        #expect(h.processes.paused.isEmpty)
        #expect(h.controller.status == .syncing(until: nil))
        #expect(!h.activity.holding)
    }

    @Test func pausedProcessExitTriggersReapply() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.processes.resume([.drive]) // simulate launchd replacing bird
        h.processes.onPausedProcessExit?()
        #expect(h.processes.paused == [.drive])
    }

    @Test func newProcessAppearingAfterExitIsPausedByFollowUp() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        #expect(h.processes.paused == [.drive])
        // bird dies; launchd starts a new one 4 s later.
        h.processes.alive = []
        h.processes.resume([.drive])
        h.processes.onPausedProcessExit?()
        h.advance(4)
        #expect(h.processes.paused.isEmpty)
        h.processes.alive = [.drive]
        h.advance(1.1)
        #expect(h.processes.paused == [.drive])
    }

    @Test func exitFollowUpsStopAfterQuit() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.processes.onPausedProcessExit?()
        h.controller.prepareToQuit()
        h.advance(12)
        #expect(h.processes.paused.isEmpty)
    }

    // MARK: Fix round 1

    @Test func failedHeartbeatNeverPauses() throws {
        let h = Harness("2026-10-12 14:00")
        try h.breakFiles()
        h.controller.start(registerHelper: {})
        #expect(h.processes.paused.isEmpty)
        #expect(h.controller.status == .helperDisabled)
    }

    @Test func heartbeatFailureOnTickResumesUntilWritesSucceed() throws {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        #expect(h.processes.paused == [.drive])
        try h.breakFiles()
        h.controller.tick()
        #expect(h.processes.paused.isEmpty)
        #expect(h.controller.status == .helperDisabled)
        #expect(!h.activity.holding)
        try h.repairFiles()
        h.controller.tick()
        #expect(h.processes.paused == [.drive])
    }

    @Test func tickAfterPowerOffDoesNotRepause() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.handlePowerOff()
        #expect(h.controller.status == .syncing(until: nil))
        h.controller.tick()
        h.processes.onPausedProcessExit?()
        #expect(h.processes.paused.isEmpty)
        #expect(!h.controller.isPausedNow)
    }

    @Test func tickAfterQuitResumeDoesNotRepause() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.prepareToQuit()
        h.controller.tick()
        #expect(h.processes.paused.isEmpty)
    }

    // MARK: Final review fixes

    @Test func cancelledLogoutReappliesScheduleAfterSixtySeconds() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.handlePowerOff()
        h.date = h.date.addingTimeInterval(30)
        h.controller.tick()
        #expect(h.processes.paused.isEmpty)
        h.date = h.date.addingTimeInterval(31) // 61 s after power-off: logout was cancelled
        h.controller.tick()
        #expect(h.processes.paused == [.drive])
        #expect(h.controller.isPausedNow)
    }

    @Test func helperDisabledWhilePausedResumesOnNextTick() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        #expect(h.processes.paused == [.drive])
        h.helperState = .disabled
        h.controller.tick()
        #expect(h.processes.paused.isEmpty)
        #expect(h.controller.status == .helperDisabled)
        #expect(!h.activity.holding)
    }

    // MARK: Deep pause: breathing

    @Test func pausedTargetsBreatheEveryTwoSeconds() {
        let h = Harness("2026-10-12 14:00")
        h.settings.pauseCloudKit = true
        h.controller.start(registerHelper: {})
        #expect(h.processes.paused == [.drive, .cloudKit])
        let mark = h.processes.log.count
        h.advance(1.79)
        #expect(h.log(since: mark).isEmpty)
        h.advance(0.02)
        #expect(h.log(since: mark) == ["release drive,cloudKit"])
        #expect(h.processes.paused.isEmpty)
        h.advance(0.2)
        #expect(h.log(since: mark) == ["release drive,cloudKit", "restop drive,cloudKit"])
        #expect(h.processes.paused == [.drive, .cloudKit])
        #expect(h.controller.isPausedNow) // breaths never change the status
        h.advance(8)
        #expect(h.log(since: mark).count == 10)
    }

    @Test func tickWhilePausedKeepsTheBreathingRhythm() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.advance(1.0)
        h.controller.tick()
        let mark = h.processes.log.count
        h.advance(0.81) // 1.81 s after the pause, not after the tick
        #expect(h.log(since: mark) == ["release drive"])
    }

    @Test func syncingNeverBreathes() {
        let h = Harness("2026-10-12 03:00") // inside the window
        h.controller.start(registerHelper: {})
        let mark = h.processes.log.count
        h.advance(10)
        #expect(h.log(since: mark).isEmpty)
    }

    @Test func switchingToSyncOnStopsBreathing() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.advance(1.9) // mid-breath
        h.settings.mode = .alwaysSync
        let mark = h.processes.log.count
        h.advance(10)
        #expect(h.log(since: mark).isEmpty)
        #expect(h.processes.paused.isEmpty)
        #expect(h.processes.released.isEmpty)
    }

    @Test func sleepStopsBreathingAndWakeRestartsIt() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.handleWillSleep()
        var mark = h.processes.log.count
        h.advance(10)
        #expect(h.log(since: mark).isEmpty)
        h.controller.handleWake()
        mark = h.processes.log.count
        h.advance(1.81)
        #expect(h.log(since: mark) == ["release drive"])
    }

    @Test func powerOffAndQuitStopBreathing() {
        for quit in [false, true] {
            let h = Harness("2026-10-12 14:00")
            h.controller.start(registerHelper: {})
            h.advance(1.9) // mid-breath: the re-stop must not fire
            if quit { h.controller.prepareToQuit() } else { h.controller.handlePowerOff() }
            let mark = h.processes.log.count
            h.advance(30)
            #expect(h.log(since: mark).isEmpty, "quit: \(quit)")
            #expect(h.processes.paused.isEmpty)
            #expect(h.processes.released.isEmpty)
        }
    }

    @Test func tickInsideTheReleaseWindowDoesNotCutTheBreathShort() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.advance(1.9) // released since 1.8 s
        #expect(h.processes.released == [.drive])
        let mark = h.processes.log.count
        h.controller.tick()
        #expect(h.processes.released == [.drive]) // still breathing
        #expect(h.processes.paused.isEmpty)
        #expect(!h.log(since: mark).contains { $0.hasPrefix("pause") }) // never re-paused mid-breath
        h.advance(0.11) // 2.0 s: the breather re-stops
        #expect(h.processes.paused == [.drive])
        h.advance(1.77) // 3.78 s: next release is 2.0 s after the previous one (3.8 s)
        #expect(h.processes.released.isEmpty)
        h.advance(0.03)
        #expect(h.processes.released == [.drive])
    }

    @Test func unticksAnOptionalTargetMidBreath() {
        let h = Harness("2026-10-12 14:00")
        h.settings.pauseCloudKit = true
        h.controller.start(registerHelper: {})
        h.advance(1.85)
        #expect(h.processes.released == [.drive, .cloudKit])
        h.settings.pauseCloudKit = false
        #expect(h.processes.released == [.drive]) // cloudKit resumed for good
        #expect(h.processes.paused.isEmpty)
        h.advance(0.15)
        #expect(h.processes.paused == [.drive])
        h.expectNextBreathWithinTwoSeconds()
    }

    @Test func ticksAnOptionalTargetMidBreath() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.advance(1.85)
        h.settings.pauseCloudKit = true
        #expect(h.processes.released == [.drive]) // breath not cut short
        #expect(h.processes.paused.isEmpty)
        h.advance(0.15)
        #expect(h.processes.paused == [.drive])
        h.controller.tick() // picked up by the next tick
        #expect(h.processes.paused == [.drive, .cloudKit])
        h.expectNextBreathWithinTwoSeconds()
    }

    @Test func launchThawStartingMidBreath() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.advance(1.85)
        h.controller.handleAppLaunch()
        #expect(h.processes.paused.isEmpty)
        #expect(h.processes.released.isEmpty)
        let mark = h.processes.log.count
        h.advance(9.9)
        #expect(h.log(since: mark).isEmpty) // the old re-stop never fires
        #expect(h.processes.paused.isEmpty)
        h.advance(0.2)
        #expect(h.processes.paused == [.drive])
        h.expectNextBreathWithinTwoSeconds()
    }

    @Test func stoppedTargetsAlwaysBreatheWithinTwoSecondsAfterMixedEvents() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        let steps: [(String, () -> Void)] = [
            ("tick", { h.controller.tick() }),
            ("tick in release", { h.advance(1.85); h.controller.tick() }),
            ("tick optional", { h.settings.pauseCloudKit = true }),
            ("settle", { h.advance(0.2); h.controller.tick() }),
            ("launch", { h.controller.handleAppLaunch() }),
            ("launch extends", { h.advance(4); h.controller.handleAppLaunch() }),
            ("thaw ends", { h.advance(10.1) }),
            ("untick optional", { h.advance(1.7); h.settings.pauseCloudKit = false }),
            ("sleep", { h.controller.handleWillSleep() }),
            ("wake", { h.advance(5); h.controller.handleWake() }),
            ("sync on", { h.settings.mode = .alwaysSync }),
            ("sync off", { h.advance(3); h.settings.mode = .alwaysPause }),
            ("probe answered", { h.probe.answer(); h.advance(0.5); h.controller.tick() }),
            ("long", { h.advance(7.3) })
        ]
        for (name, step) in steps {
            step()
            h.probe.answer() // iCloud keeps answering: no cooldown in this scenario
            h.expectNextBreathWithinTwoSeconds("after \(name)")
            // and again at a few offsets: the invariant holds between events too
            for _ in 0..<5 {
                h.advance(0.37)
                h.probe.answer()
                h.expectNextBreathWithinTwoSeconds("after \(name) + drift")
            }
        }
        #expect(h.controller.isPausedNow)
    }

    // MARK: Deep pause: launch thaw

    @Test func appLaunchThawsForTenSecondsThenPausesAgain() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.handleAppLaunch()
        #expect(h.processes.paused.isEmpty)
        #expect(h.controller.isPausedNow) // no flicker in the menu for a 10 s thaw
        #expect(h.activity.holding)
        let mark = h.processes.log.count
        h.advance(9.9)
        #expect(h.log(since: mark).isEmpty) // no breathing while thawed
        h.advance(0.2)
        #expect(h.processes.paused == [.drive])
        h.advance(1.81)
        #expect(h.log(since: mark).last == "release drive")
    }

    @Test func anotherLaunchExtendsTheThaw() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.handleAppLaunch() // willLaunch
        h.advance(6)
        h.controller.handleAppLaunch() // another app
        h.advance(6)
        #expect(h.processes.paused.isEmpty)
        h.controller.tick() // a tick during the thaw must not re-pause
        #expect(h.processes.paused.isEmpty)
        h.advance(4.1)
        #expect(h.processes.paused == [.drive])
    }

    @Test func appLaunchWhileSyncingChangesNothing() {
        let h = Harness("2026-10-12 03:00")
        h.controller.start(registerHelper: {})
        let mark = h.processes.log.count
        h.controller.handleAppLaunch()
        h.advance(11)
        #expect(h.processes.paused.isEmpty)
        #expect(h.controller.status == .syncing(until: TestTime.date("2026-10-12 09:00")))
        #expect(h.log(since: mark).allSatisfy { $0.hasPrefix("resume") })
    }

    @Test func appLaunchAfterQuitOrDuringSleepIsIgnored() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.handleWillSleep()
        h.controller.handleAppLaunch()
        h.advance(11)
        #expect(h.processes.paused.isEmpty)
        h.controller.handleWake()
        #expect(h.processes.paused == [.drive])
        h.controller.prepareToQuit()
        h.controller.handleAppLaunch()
        h.advance(11)
        #expect(h.processes.paused.isEmpty)
    }

    @Test func sleepEndsTheThaw() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.handleAppLaunch()
        h.controller.handleWillSleep()
        h.controller.handleWake()
        #expect(h.processes.paused == [.drive])
    }

    // MARK: Deep pause: health check

    @Test func healthCheckConstants() {
        #expect(SyncController.launchThawDuration == 10)
        #expect(SyncController.probeTimeout == 3.0)
        #expect(SyncController.probeTimeout > Breather.breathInterval)
        #expect(SyncController.cooldownDuration == 600)
    }

    @Test func tickWhilePausedProbesICloud() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        #expect(h.probe.pings == 0)
        h.controller.tick()
        #expect(h.probe.pings == 1)
        h.advance(1.5)
        h.probe.answer()
        h.advance(30)
        h.controller.tick()
        #expect(h.probe.pings == 2)
        #expect(h.controller.isPausedNow)
    }

    @Test func noProbeWhileSyncingThawedOrUnableToPause() {
        let syncing = Harness("2026-10-12 03:00")
        syncing.controller.start(registerHelper: {})
        syncing.controller.tick()
        #expect(syncing.probe.pings == 0)

        let thawed = Harness("2026-10-12 14:00")
        thawed.controller.start(registerHelper: {})
        thawed.controller.handleAppLaunch()
        thawed.controller.tick()
        #expect(thawed.probe.pings == 0)

        let disabled = Harness("2026-10-12 14:00")
        disabled.helperState = .disabled
        disabled.controller.start(registerHelper: {})
        disabled.controller.tick()
        #expect(disabled.probe.pings == 0)
    }

    @Test func onlyOneProbeInFlight() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.tick()
        h.advance(1)
        h.controller.tick()
        #expect(h.probe.pings == 1)
        h.advance(30) // timed out: cooldown, but the call is still hanging
        h.date = h.date.addingTimeInterval(11 * 60)
        h.controller.tick() // cooldown over, paused again
        #expect(h.controller.isPausedNow)
        h.controller.tick()
        #expect(h.probe.pings == 1) // never a second call while the first hangs
        h.probe.answer()
        h.controller.tick()
        #expect(h.probe.pings == 2)
    }

    @Test func slowButAnsweredProbeKeepsPausing() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.tick()
        h.advance(2.9)
        h.probe.answer()
        h.advance(10)
        #expect(h.controller.isPausedNow)
        #expect(h.processes.paused == [.drive])
    }

    @Test func probeTimeoutResumesEverythingForTenMinutes() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        let probedAt = h.date
        h.controller.tick()
        h.advance(2.99)
        #expect(h.controller.isPausedNow)
        h.advance(0.02) // 3 s without an answer
        let cooldownEnd = probedAt.addingTimeInterval(SyncController.probeTimeout)
            .addingTimeInterval(SyncController.cooldownDuration)
        #expect(h.processes.paused.isEmpty)
        #expect(h.controller.status == .syncing(until: cooldownEnd))
        #expect(!h.activity.holding)
        let mark = h.processes.log.count
        h.advance(10)
        #expect(h.log(since: mark).isEmpty) // no breathing in cooldown
        h.probe.answer() // late answer: still cooling down
        h.date = h.date.addingTimeInterval(5 * 60)
        h.controller.tick()
        #expect(h.processes.paused.isEmpty)
        #expect(h.probe.pings == 1)
        h.date = cooldownEnd
        h.controller.tick()
        #expect(h.processes.paused == [.drive])
        #expect(h.controller.status == .paused(until: TestTime.date("2026-10-13 02:00")))
        h.controller.tick()
        #expect(h.probe.pings == 2) // tries again
    }

    @Test func cooldownInSyncOffShowsWhenPausingResumes() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.settings.mode = .alwaysPause
        let probedAt = h.date
        h.controller.tick()
        h.advance(3.01)
        let cooldownEnd = probedAt.addingTimeInterval(SyncController.probeTimeout)
            .addingTimeInterval(SyncController.cooldownDuration)
        #expect(h.controller.status == .syncing(until: cooldownEnd))
    }

    @Test func cooldownEndingAfterTheWindowOpensShowsPlainSyncing() {
        let h = Harness("2026-10-12 01:55")
        h.controller.start(registerHelper: {})
        h.controller.tick()
        h.advance(3.01) // cooldown until 02:05, window opens 02:00
        #expect(h.controller.status == .syncing(until: nil))
        h.at("2026-10-12 02:01")
        h.controller.tick()
        #expect(h.controller.status == .syncing(until: TestTime.date("2026-10-12 09:00")))
    }

    @Test func sleepCancelsAPendingProbeTimeout() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.tick() // timeout would fire 3 s after the tick
        h.advance(1)
        h.controller.handleWillSleep()
        h.advance(0.5)
        h.controller.handleWake() // awake and breathing again before the old deadline
        h.advance(3) // past the old deadline
        #expect(h.controller.status == .paused(until: TestTime.date("2026-10-13 02:00")))
        #expect(h.controller.isPausedNow)
        #expect(h.processes.paused == [.drive] || h.processes.released == [.drive])
    }

    @Test func probeTimeoutDuringLaunchThawIsNoCooldown() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.tick()
        h.advance(1)
        h.controller.handleAppLaunch() // targets run: a hanging probe proves nothing
        h.advance(2.5) // the probe deadline passes inside the thaw
        #expect(h.controller.status == .paused(until: TestTime.date("2026-10-13 02:00")))
        h.advance(10) // thaw over
        #expect(h.processes.paused == [.drive])
        #expect(h.controller.status == .paused(until: TestTime.date("2026-10-13 02:00")))
    }

    @Test func probeTimeoutAfterSwitchingToSyncOnIsNoCooldown() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.tick()
        h.advance(1)
        h.settings.mode = .alwaysSync
        h.advance(3) // the deadline passes while syncing
        h.settings.mode = .alwaysPause
        #expect(h.controller.status == .paused(until: nil))
        #expect(h.processes.paused == [.drive])
    }

    @Test func clockSetBackEndsCooldown() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.tick()
        h.advance(3.01)
        #expect(!h.controller.isPausedNow)
        h.date = h.date.addingTimeInterval(-3600)
        h.probe.answer()
        h.controller.tick()
        #expect(h.controller.isPausedNow)
    }
}
