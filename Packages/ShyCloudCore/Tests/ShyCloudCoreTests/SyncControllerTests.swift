import Foundation
import Testing
@testable import ShyCloudCore

@MainActor
final class FakeProcesses: ProcessControlling {
    var onPausedProcessExit: (@MainActor () -> Void)?
    private(set) var paused: Set<PauseTarget> = []
    private(set) var log: [String] = []

    func pause(_ targets: [PauseTarget]) {
        paused.formUnion(targets)
        if !targets.isEmpty { log.append("pause") }
    }

    func resume(_ targets: [PauseTarget]) {
        paused.subtract(targets)
        if !targets.isEmpty { log.append("resume") }
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
    let processes = FakeProcesses()
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

    init(_ text: String) {
        date = TestTime.date(text)
        let name = "shycloud-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        settings = AppSettings(defaults: defaults)
        files = SafetyFiles(directory: FileManager.default.temporaryDirectory.appending(path: name))
    }

    func at(_ text: String) { date = TestTime.date(text) }
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
        let h = Harness("2026-10-12 14:00")
        try h.files.writeKeepPaused([ProcessIdentity(pid: 1, startTime: 1)])
        var pausedWhenRegistering: Set<PauseTarget>?
        h.controller.start(registerHelper: { pausedWhenRegistering = h.processes.paused })
        #expect(h.files.readKeepPaused() == nil)
        #expect(h.files.readHeartbeat() == h.date)
        #expect(h.processes.log.first == "resume")
        #expect(pausedWhenRegistering == [])
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
}
