import Darwin
import Foundation
import Testing
@testable import ShyCloudCore

final class FakeInspector: ProcessInspecting, @unchecked Sendable {
    var table: [ProcessIdentity: PauseTarget] = [:]
    var stopped: Set<ProcessIdentity> = []
    /// Identities whose re-verification fails (simulates pid reuse between list and signal).
    var revoked: Set<ProcessIdentity> = []
    private var listed: Set<ProcessIdentity> = []

    func processes(for target: PauseTarget) -> [ProcessIdentity] {
        let ids = table.filter { $0.value == target }.map(\.key).sorted { $0.pid < $1.pid }
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
    let inspector: FakeInspector
    init(_ inspector: FakeInspector) { self.inspector = inspector }

    func send(_ signal: Int32, to pid: Int32) -> Bool {
        sent.append((signal, pid))
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

    @Test func realInspectorNeverFindsUnlistedProcesses() {
        // Real inspector + recording signaler: pausing must only ever target allowlisted paths.
        let recorder = RecordingSignaler()
        let controller = SignalProcessController(inspector: DarwinProcessInspector(), signaler: recorder, watchExits: false)
        controller.pause([])
        #expect(recorder.sent.isEmpty)
    }
}

final class RecordingSignaler: Signaling, @unchecked Sendable {
    var sent: [(Int32, Int32)] = []
    func send(_ signal: Int32, to pid: Int32) -> Bool {
        sent.append((signal, pid))
        return true
    }
}
