import Foundation
import Testing
@testable import ShyCloudCore

struct SafetyTests {
    func tempFiles() -> SafetyFiles {
        SafetyFiles(directory: FileManager.default.temporaryDirectory.appending(path: "shycloud-tests-\(UUID().uuidString)"))
    }

    @Test func heartbeatRoundTrip() throws {
        let files = tempFiles()
        #expect(files.readHeartbeat() == nil)
        let date = Date(timeIntervalSince1970: 1_800_000_000.5)
        try files.writeHeartbeat(date)
        #expect(files.readHeartbeat() == date)
    }

    @Test func keepPausedRoundTripAndDelete() throws {
        let files = tempFiles()
        let ids = [ProcessIdentity(pid: 42, startTime: 7)]
        try files.writeKeepPaused(ids)
        #expect(files.readKeepPaused() == ids)
        files.deleteKeepPaused()
        #expect(files.readKeepPaused() == nil)
        files.deleteKeepPaused() // deleting twice is fine
    }

    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let paused = [ProcessIdentity(pid: 42, startTime: 7)]

    @Test func freshHeartbeatExits() {
        #expect(WatchdogDecision.decide(heartbeat: now.addingTimeInterval(-60), now: now, keepPaused: nil, isAliveAndStopped: { _ in false }) == .exit)
        #expect(WatchdogDecision.decide(heartbeat: now.addingTimeInterval(-120), now: now, keepPaused: nil, isAliveAndStopped: { _ in false }) == .exit)
    }

    @Test func staleHeartbeatResumes() {
        #expect(WatchdogDecision.decide(heartbeat: now.addingTimeInterval(-121), now: now, keepPaused: nil, isAliveAndStopped: { _ in false }) == .resume)
        #expect(WatchdogDecision.decide(heartbeat: nil, now: now, keepPaused: nil, isAliveAndStopped: { _ in false }) == .resume)
    }

    @Test func validKeepPausedRecordIsHonoured() {
        #expect(WatchdogDecision.decide(heartbeat: nil, now: now, keepPaused: paused, isAliveAndStopped: { _ in true }) == .exit)
    }

    @Test func staleKeepPausedRecordResumes() {
        #expect(WatchdogDecision.decide(heartbeat: nil, now: now, keepPaused: paused, isAliveAndStopped: { _ in false }) == .resume)
        #expect(WatchdogDecision.decide(heartbeat: nil, now: now, keepPaused: [], isAliveAndStopped: { _ in true }) == .resume)
    }
}
