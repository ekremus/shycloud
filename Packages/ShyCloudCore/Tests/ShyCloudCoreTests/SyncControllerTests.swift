import Foundation
import Testing
@testable import ShyCloudCore

@MainActor
final class FakeProcesses: ProcessControlling {
    var onPausedProcessExit: (@MainActor () -> Void)?
    private(set) var paused: Set<PauseTarget>
    /// One entry per non-empty call, e.g. "resume drive,photoAnalysis,cloudKit" (pause order).
    private(set) var log: [String] = []

    init(paused: Set<PauseTarget> = []) {
        self.paused = paused
    }

    func pause(_ targets: [PauseTarget]) {
        paused.formUnion(targets)
        record("pause", targets)
    }

    func resume(_ targets: [PauseTarget]) {
        paused.subtract(targets)
        record("resume", targets)
    }

    private func record(_ action: String, _ targets: [PauseTarget]) {
        guard !targets.isEmpty else { return }
        let names = PauseTarget.pauseOrder.filter(targets.contains).map(\.rawValue)
        log.append("\(action) \(names.joined(separator: ","))")
    }

    func pausedProcesses() -> [ProcessIdentity] {
        PauseTarget.pauseOrder.filter(paused.contains).enumerated().map {
            ProcessIdentity(pid: Int32(100 + $0.offset), startTime: 1)
        }
    }
}

@MainActor
final class FakeActivity: ActivityHolding {
    var holding = false
    func setHolding(_ holding: Bool) { self.holding = holding }
}

@MainActor
final class Harness {
    var date: Date
    var helperEnabled = true
    let settings: AppSettings
    let processes: FakeProcesses
    let activity = FakeActivity()
    let files: SafetyFiles
    lazy var controller = SyncController(
        settings: settings,
        processes: processes,
        files: files,
        activity: activity,
        now: { [unowned self] in self.date },
        calendar: { TestTime.calendar() },
        isHelperEnabled: { [unowned self] in self.helperEnabled }
    )

    /// `paused` simulates targets left stopped by a previous crash.
    init(_ text: String, paused: Set<PauseTarget> = []) {
        date = TestTime.date(text)
        processes = FakeProcesses(paused: paused)
        let name = "shycloud-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        settings = AppSettings(defaults: defaults)
        files = SafetyFiles(directory: FileManager.default.temporaryDirectory.appending(path: name))
    }

    func at(_ text: String) { date = TestTime.date(text) }

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
        h.helperEnabled = false
        h.controller.start(registerHelper: {})
        #expect(h.processes.paused.isEmpty)
        #expect(h.controller.status == .helperDisabled)
        #expect(!h.controller.isPausedNow)
    }

    @Test func launchOrderClearsFlagWritesHeartbeatResumesThenRegisters() throws {
        let h = Harness("2026-10-12 14:00", paused: Set(PauseTarget.allCases)) // previous crash
        try h.files.writeKeepPaused([ProcessIdentity(pid: 1, startTime: 1)])
        var keepPausedWhenRegistering: [ProcessIdentity]?? = .none
        var heartbeatWhenRegistering: Date?
        var pausedWhenRegistering: Set<PauseTarget>?
        h.controller.start(registerHelper: {
            keepPausedWhenRegistering = .some(h.files.readKeepPaused())
            heartbeatWhenRegistering = h.files.readHeartbeat()
            pausedWhenRegistering = h.processes.paused
        })
        #expect(keepPausedWhenRegistering == .some(nil))
        #expect(heartbeatWhenRegistering == h.date)
        #expect(pausedWhenRegistering == [])
        #expect(h.processes.log.first == "resume drive,photoAnalysis,cloudKit")
    }

    @Test func firstLaunchDoesNotCatchUp() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        #expect(h.settings.lastSyncedAt == h.date)
        #expect(h.controller.isPausedNow)
    }

    @Test func staleSyncTriggersCatchUpThenPauses() {
        let h = Harness("2026-10-12 14:00")
        h.settings.lastSyncedAt = TestTime.date("2026-10-11 08:00")
        h.controller.start(registerHelper: {})
        #expect(h.processes.paused.isEmpty)
        #expect(h.controller.status == .catchingUp(until: TestTime.date("2026-10-12 14:30")))
        h.at("2026-10-12 14:30")
        h.controller.tick()
        #expect(h.processes.paused == [.drive])
        #expect(h.settings.lastSyncedAt == TestTime.date("2026-10-12 14:30"))
    }

    @Test func wakeAfterMissedWindowCatchesUp() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.handleWillSleep()
        h.at("2026-10-13 15:00") // slept through the whole window
        h.controller.handleWake()
        #expect(h.controller.status == .catchingUp(until: TestTime.date("2026-10-13 15:30")))
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

    @Test func quitKeepPausedWritesRecord() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.prepareToQuit(keepPaused: true)
        #expect(h.processes.paused == [.drive])
        #expect(h.files.readKeepPaused() == [ProcessIdentity(pid: 100, startTime: 1)])
        #expect(!h.activity.holding)
    }

    @Test func quitResumeResumesAndWritesNothing() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.controller.prepareToQuit(keepPaused: false)
        #expect(h.processes.paused.isEmpty)
        #expect(h.files.readKeepPaused() == nil)
    }

    @Test func pausedProcessExitTriggersReapply() {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        h.processes.resume([.drive]) // simulate launchd replacing bird
        h.processes.onPausedProcessExit?()
        #expect(h.processes.paused == [.drive])
    }

    // MARK: Fix round 1

    @Test func sleepCutsCatchUpShortAndNextWakeCatchesUpAgain() {
        let h = Harness("2026-10-12 14:00")
        h.settings.lastSyncedAt = TestTime.date("2026-10-11 08:00")
        h.controller.start(registerHelper: {})
        #expect(h.controller.status == .catchingUp(until: TestTime.date("2026-10-12 14:30")))
        h.at("2026-10-12 14:10")
        h.controller.handleWillSleep()
        h.at("2026-10-13 15:00")
        h.controller.handleWake()
        #expect(h.controller.status == .catchingUp(until: TestTime.date("2026-10-13 15:30")))
        #expect(h.processes.paused.isEmpty)
    }

    @Test func catchUpRunningIntoWindowReportsWindowEnd() {
        let h = Harness("2026-10-12 01:45")
        h.settings.lastSyncedAt = TestTime.date("2026-10-10 19:45") // 30 h old
        h.controller.start(registerHelper: {})
        h.at("2026-10-12 01:50")
        h.controller.tick()
        #expect(h.controller.status == .catchingUp(until: TestTime.date("2026-10-12 09:00")))
        h.at("2026-10-12 02:05")
        h.controller.tick()
        #expect(h.controller.status == .syncing(until: TestTime.date("2026-10-12 09:00")))
    }

    @Test func quitKeepPausedResumesWhenRecordCannotBeWritten() throws {
        let h = Harness("2026-10-12 14:00")
        h.controller.start(registerHelper: {})
        #expect(h.processes.paused == [.drive])
        try h.breakFiles()
        h.controller.prepareToQuit(keepPaused: true)
        #expect(h.processes.paused.isEmpty)
        #expect(h.files.readKeepPaused() == nil)
        #expect(!h.activity.holding)
    }

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
        h.controller.prepareToQuit(keepPaused: false)
        h.controller.tick()
        #expect(h.processes.paused.isEmpty)
    }

    @Test func quitKeepPausedRefreshesStateFirst() {
        let h = Harness("2026-10-12 08:59")
        h.controller.start(registerHelper: {})
        #expect(!h.controller.isPausedNow)
        h.at("2026-10-12 09:00") // window just closed, no tick yet
        h.controller.prepareToQuit(keepPaused: true)
        #expect(h.processes.paused == [.drive])
        #expect(h.files.readKeepPaused() == [ProcessIdentity(pid: 100, startTime: 1)])
    }
}
