import Foundation
import Testing
@testable import ShyCloudCore

struct SafetyTests {
    func tempFiles() -> SafetyFiles {
        SafetyFiles(directory: FileManager.default.temporaryDirectory.appending(path: "shycloud-tests-\(UUID().uuidString)"))
    }

    /// Runs `body` with a fresh SafetyFiles and removes its directory afterwards.
    func withTempFiles<T>(_ body: (SafetyFiles) throws -> T) rethrows -> T {
        let files = tempFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        return try body(files)
    }

    func writeRaw(_ text: String, to url: URL, in files: SafetyFiles) throws {
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func heartbeatRoundTrip() throws {
        try withTempFiles { files in
        #expect(files.readHeartbeat() == nil)
        let date = Date(timeIntervalSince1970: 1_800_000_000.5)
        try files.writeHeartbeat(date)
        #expect(files.readHeartbeat() == date)
        }
    }

    let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func freshHeartbeatExits() {
        #expect(WatchdogDecision.decide(heartbeat: now.addingTimeInterval(-60), now: now) == .exit)
        #expect(WatchdogDecision.decide(heartbeat: now.addingTimeInterval(-120), now: now) == .exit)
    }

    @Test func staleHeartbeatResumes() {
        #expect(WatchdogDecision.decide(heartbeat: now.addingTimeInterval(-121), now: now) == .resume)
        #expect(WatchdogDecision.decide(heartbeat: nil, now: now) == .resume)
    }

    // MARK: fail-safe (corrupt or doubtful input must lead to resume)

    @Test func garbageHeartbeatIsNil() throws {
        try withTempFiles { files in
            try writeRaw("not a number", to: files.heartbeatURL, in: files)
            #expect(files.readHeartbeat() == nil)
        }
    }

    @Test func nonFiniteHeartbeatIsNil() throws {
        try withTempFiles { files in
            for text in ["inf", "-inf", "nan", "infinity"] {
                try writeRaw(text, to: files.heartbeatURL, in: files)
                #expect(files.readHeartbeat() == nil, "\(text)")
            }
        }
    }

    @Test func heartbeatWithTrailingNewlineParses() throws {
        try withTempFiles { files in
            try writeRaw("1800000000.5\n", to: files.heartbeatURL, in: files)
            #expect(files.readHeartbeat() == Date(timeIntervalSince1970: 1_800_000_000.5))
        }
    }

    @Test func futureHeartbeatResumes() {
        #expect(WatchdogDecision.decide(heartbeat: now.addingTimeInterval(3600), now: now) == .resume)
    }

    @Test func slightlyFutureHeartbeatExits() {
        #expect(WatchdogDecision.decide(heartbeat: now.addingTimeInterval(30), now: now) == .exit)
    }

    // MARK: watchdog liveness (spec §5.5/5.7)

    @Test func watchdogRanRoundTrip() throws {
        try withTempFiles { files in
            #expect(files.readWatchdogRan() == nil)
            let date = Date(timeIntervalSince1970: 1_800_000_000.5)
            try files.writeWatchdogRan(date)
            #expect(files.readWatchdogRan() == date)
        }
    }

    @Test func corruptWatchdogRanIsNil() throws {
        try withTempFiles { files in
            for text in ["garbage", "inf", "-inf", "nan", ""] {
                try writeRaw(text, to: files.watchdogRanURL, in: files)
                #expect(files.readWatchdogRan() == nil, "\(text)")
            }
        }
    }

    @Test func watchdogAliveWithinWindow() {
        #expect(WatchdogDecision.isWatchdogAlive(lastRun: now, now: now))
        #expect(WatchdogDecision.isWatchdogAlive(lastRun: now.addingTimeInterval(-180), now: now))
        #expect(WatchdogDecision.isWatchdogAlive(lastRun: now.addingTimeInterval(60), now: now))
    }

    @Test func watchdogNotAliveWhenMissingStaleOrFarFuture() {
        #expect(!WatchdogDecision.isWatchdogAlive(lastRun: nil, now: now))
        #expect(!WatchdogDecision.isWatchdogAlive(lastRun: now.addingTimeInterval(-181), now: now))
        #expect(!WatchdogDecision.isWatchdogAlive(lastRun: now.addingTimeInterval(61), now: now))
    }

    @Test func missingDirectoryReadsNil() {
        let files = tempFiles()
        #expect(files.readHeartbeat() == nil)
        #expect(files.readWatchdogRan() == nil)
    }
}
