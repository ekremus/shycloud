import Darwin
import Foundation
import Testing
@testable import ShyCloudCore

final class FakeInspector: ProcessInspecting, @unchecked Sendable {
    var table: [ProcessIdentity: PauseTarget] = [:]
    var stopped: Set<ProcessIdentity> = []
    /// Identities whose re-verification fails (simulates pid reuse between list and signal).
    var revoked: Set<ProcessIdentity> = []
    /// Identities omitted from `processes(for:)` (simulates a missed scan) but still verifiable.
    var hidden: Set<ProcessIdentity> = []
    private var listed: Set<ProcessIdentity> = []

    func processes(for target: PauseTarget) -> [ProcessIdentity] {
        let ids = table.filter { $0.value == target && !hidden.contains($0.key) }.map(\.key).sorted { $0.pid < $1.pid }
        listed.formUnion(ids)
        return ids
    }

    func target(of id: ProcessIdentity) -> PauseTarget? {
        if listed.contains(id), revoked.contains(id) { return nil }
        return table[id]
    }

    func isStopped(_ id: ProcessIdentity) -> Bool { stopped.contains(id) }
}

final class FakeSignaler: Signaling, @unchecked Sendable {
    var sent: [(Int32, Int32)] = []
    var failPids: Set<Int32> = []
    let inspector: FakeInspector
    init(_ inspector: FakeInspector) { self.inspector = inspector }

    func send(_ signal: Int32, to pid: Int32) -> Bool {
        sent.append((signal, pid))
        if failPids.contains(pid) { return false }
        for id in inspector.table.keys where id.pid == pid {
            if signal == SIGSTOP { inspector.stopped.insert(id) }
            if signal == SIGCONT { inspector.stopped.remove(id) }
        }
        return true
    }
}

@MainActor
struct SignalProcessControllerTests {
    let bird = ProcessIdentity(pid: 10, startTime: 1)
    let photo = ProcessIdentity(pid: 20, startTime: 1)
    let cloudd = ProcessIdentity(pid: 30, startTime: 1)
    let cloudphotod = ProcessIdentity(pid: 40, startTime: 1)

    func make() -> (SignalProcessController, FakeInspector, FakeSignaler) {
        let inspector = FakeInspector()
        inspector.table = [bird: .drive, photo: .photoAnalysis, cloudd: .cloudKit]
        let signaler = FakeSignaler(inspector)
        let controller = SignalProcessController(inspector: inspector, signaler: signaler, watchExits: false)
        return (controller, inspector, signaler)
    }

    @Test func pauseStopsOnlyRequestedTargetsInOrder() {
        let (controller, _, signaler) = make()
        controller.pause([.cloudKit, .drive])
        #expect(signaler.sent.map { $0.0 } == [SIGSTOP, SIGSTOP])
        #expect(signaler.sent.map { $0.1 } == [10, 30])
        #expect(controller.pausedProcesses() == [bird, cloudd])
    }

    @Test func resumeContinuesInReverseOrder() {
        let (controller, _, signaler) = make()
        controller.pause(PauseTarget.allCases)
        signaler.sent.removeAll()
        controller.resumeAll()
        #expect(signaler.sent.map { $0.0 } == [SIGCONT, SIGCONT, SIGCONT])
        #expect(signaler.sent.map { $0.1 } == [30, 20, 10])
        #expect(controller.pausedProcesses().isEmpty)
    }

    @Test func photosSitsBetweenDriveAndPhotoAnalysis() {
        let (controller, inspector, signaler) = make()
        inspector.table[cloudphotod] = .photos
        controller.pause(PauseTarget.allCases)
        #expect(signaler.sent.map { $0.1 } == [10, 40, 20, 30])
        signaler.sent.removeAll()
        controller.resumeAll()
        #expect(signaler.sent.map { $0.1 } == [30, 20, 40, 10])
    }

    @Test func partialResumeKeepsOthersPaused() {
        let (controller, _, _) = make()
        controller.pause(PauseTarget.allCases)
        controller.resume([.cloudKit])
        #expect(controller.pausedProcesses() == [bird, photo])
    }

    @Test func reverificationFailureMeansNoSignal() {
        let (controller, inspector, signaler) = make()
        inspector.revoked = [bird]
        controller.pause([.drive])
        #expect(signaler.sent.isEmpty)
        #expect(controller.pausedProcesses().isEmpty)
    }

    @Test func pausingTwiceIsHarmless() {
        let (controller, _, _) = make()
        controller.pause([.drive])
        controller.pause([.drive])
        #expect(controller.pausedProcesses() == [bird])
    }

    @Test func failedContinueKeepsProcessTracked() {
        let (controller, inspector, signaler) = make()
        controller.pause([.drive])
        signaler.failPids = [10]
        controller.resume([.drive])
        #expect(controller.pausedProcesses() == [bird])
        signaler.failPids = []
        controller.resume([.drive])
        #expect(inspector.stopped.isEmpty)
        #expect(controller.pausedProcesses().isEmpty)
    }

    @Test func pausedButUnlistedProcessIsStillContinued() {
        let (controller, inspector, signaler) = make()
        controller.pause([.drive])
        inspector.hidden = [bird]
        signaler.sent.removeAll()
        controller.resume([.drive])
        #expect(signaler.sent.map { $0.0 } == [SIGCONT])
        #expect(signaler.sent.map { $0.1 } == [10])
        #expect(controller.pausedProcesses().isEmpty)
    }

    @Test func partialResumeDropsDeadIdsAndKeepsLiveOnes() {
        let (controller, inspector, _) = make()
        controller.pause(PauseTarget.allCases)
        inspector.table[bird] = nil
        inspector.stopped.remove(bird)
        controller.resume([.cloudKit])
        #expect(controller.pausedProcesses() == [photo])
        // photo must still be tracked: resuming its target continues it.
        controller.resume([.photoAnalysis])
        #expect(inspector.stopped.isEmpty)
    }

    @Test func processExitRemovesTrackingAndFiresCallbackOnce() {
        let (controller, _, _) = make()
        var calls = 0
        controller.onPausedProcessExit = { calls += 1 }
        controller.pause([.drive])
        controller.processDidExit(bird)
        controller.processDidExit(bird)
        #expect(controller.pausedProcesses().isEmpty)
        #expect(calls == 1)
    }

    // MARK: breathing (deep pause)

    @Test func breathReleasesInResumeOrderAndRestopsInPauseOrder() {
        let (controller, inspector, signaler) = make()
        controller.pause(PauseTarget.allCases)
        signaler.sent.removeAll()
        controller.releaseForBreath()
        #expect(signaler.sent.map { $0.0 } == [SIGCONT, SIGCONT, SIGCONT])
        #expect(signaler.sent.map { $0.1 } == [30, 20, 10])
        #expect(inspector.stopped.isEmpty)
        signaler.sent.removeAll()
        controller.restopAfterBreath()
        #expect(signaler.sent.map { $0.0 } == [SIGSTOP, SIGSTOP, SIGSTOP])
        #expect(signaler.sent.map { $0.1 } == [10, 20, 30])
        #expect(controller.pausedProcesses() == [bird, photo, cloudd])
    }

    @Test func breathKeepsProcessesTrackedSoAFullResumeStillContinuesThem() {
        let (controller, inspector, _) = make()
        controller.pause([.drive])
        controller.releaseForBreath()
        controller.restopAfterBreath()
        controller.resume([.drive])
        #expect(inspector.stopped.isEmpty)
        #expect(controller.pausedProcesses().isEmpty)
    }

    @Test func breathOnlyTouchesProcessesShyCloudPaused() {
        let (controller, inspector, signaler) = make()
        controller.pause([.drive])
        let respawned = ProcessIdentity(pid: 11, startTime: 2)
        inspector.table[respawned] = .drive // not paused yet: the next apply picks it up
        signaler.sent.removeAll()
        controller.releaseForBreath()
        controller.restopAfterBreath()
        #expect(signaler.sent.map { $0.1 } == [10, 10])
    }

    @Test func breathReverifiesBeforeEverySignal() {
        let (controller, inspector, signaler) = make()
        controller.pause([.drive, .cloudKit])
        inspector.revoked = [bird] // pid reused since it was paused
        signaler.sent.removeAll()
        controller.releaseForBreath()
        controller.restopAfterBreath()
        #expect(signaler.sent.map { $0.1 } == [30, 30])
    }

    @Test func restopAfterFullResumeDoesNothing() {
        let (controller, _, signaler) = make()
        controller.pause([.drive])
        controller.releaseForBreath()
        controller.resumeAll()
        signaler.sent.removeAll()
        controller.restopAfterBreath()
        #expect(signaler.sent.isEmpty)
    }

    @Test func signalerRejectsNonPositivePids() {
        #expect(DarwinSignaler().send(0, to: 0) == false)
        #expect(DarwinSignaler().send(0, to: -1) == false)
    }

    @Test func realInspectorOnlyTargetsAllowlistedOwnProcesses() {
        // Real inspector + recording signaler (never DarwinSignaler): nothing is signalled.
        let recorder = RecordingSignaler()
        let controller = SignalProcessController(inspector: DarwinProcessInspector(), signaler: recorder, watchExits: false)
        controller.pause(PauseTarget.allCases)
        for (signal, pid) in recorder.sent {
            #expect(signal == SIGSTOP)
            var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let length = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
            #expect(length > 0)
            let path = String(decoding: buffer.prefix(Int(max(length, 0))), as: UTF8.self)
            #expect(PauseTarget.target(forExecutablePath: path) != nil)
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
            let got = withUnsafeMutablePointer(to: &info) { proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, size) }
            #expect(got == size)
            #expect(info.pbi_uid == getuid())
        }
    }
}

final class RecordingSignaler: Signaling, @unchecked Sendable {
    var sent: [(Int32, Int32)] = []
    func send(_ signal: Int32, to pid: Int32) -> Bool {
        sent.append((signal, pid))
        return true
    }
}
