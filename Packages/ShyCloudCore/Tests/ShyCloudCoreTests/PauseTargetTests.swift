import Darwin
import Foundation
import Testing
@testable import ShyCloudCore

struct PauseTargetTests {
    @Test func birdPathsMapToDrive() {
        #expect(PauseTarget.target(forExecutablePath: "/System/Library/PrivateFrameworks/iCloudDriveCore.framework/Versions/A/Support/bird") == .drive)
        #expect(PauseTarget.target(forExecutablePath: "/System/Library/PrivateFrameworks/CloudDocsDaemon.framework/Versions/A/Support/bird") == .drive)
    }

    @Test func clouddAndPhotoAnalysisPaths() {
        #expect(PauseTarget.target(forExecutablePath: "/System/Library/PrivateFrameworks/CloudKitDaemon.framework/Support/cloudd") == .cloudKit)
        #expect(PauseTarget.target(forExecutablePath: "/System/Library/PrivateFrameworks/PhotoAnalysis.framework/Versions/A/Support/photoanalysisd") == .photoAnalysis)
    }

    @Test func simulatorCopiesAreNeverTargets() {
        let simCloudd = "/Library/Developer/CoreSimulator/Volumes/iOS_23F77/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 26.5.simruntime/Contents/Resources/RuntimeRoot/System/Library/PrivateFrameworks/CloudKitDaemon.framework/Support/cloudd"
        #expect(PauseTarget.target(forExecutablePath: simCloudd) == nil)
        #expect(PauseTarget.target(forExecutablePath: "/usr/local/bin/bird") == nil)
        #expect(PauseTarget.target(forExecutablePath: "bird") == nil)
    }

    @Test func everyAllowlistedPathIsAbsoluteUnderSystemLibrary() {
        for target in PauseTarget.allCases {
            #expect(!target.executablePaths.isEmpty)
            for path in target.executablePaths {
                #expect(path.hasPrefix("/System/Library/PrivateFrameworks/"))
            }
        }
    }

    @Test func orders() {
        #expect(PauseTarget.pauseOrder == [.drive, .photoAnalysis, .cloudKit])
        #expect(PauseTarget.resumeOrder == [.cloudKit, .photoAnalysis, .drive])
    }

    @Test func inspectorSeesOwnProcessButNeverTargetsIt() throws {
        let inspector = DarwinProcessInspector()
        let me = try #require(inspector.identity(of: getpid()))
        #expect(me.pid == getpid())
        #expect(me.startTime > 0)
        #expect(inspector.target(of: me) == nil)
        #expect(!inspector.isStopped(me))
    }

    @Test func staleIdentityIsRejected() throws {
        let inspector = DarwinProcessInspector()
        let me = try #require(inspector.identity(of: getpid()))
        let wrongStart = ProcessIdentity(pid: me.pid, startTime: me.startTime + 1)
        #expect(!inspector.isStopped(wrongStart))
    }

    @Test func otherUsersProcessesAreIgnored() {
        // launchd (pid 1) runs as root; an inspector for our uid must not report it.
        let inspector = DarwinProcessInspector()
        for target in PauseTarget.allCases {
            #expect(!inspector.processes(for: target).contains { $0.pid == 1 })
        }
    }
}
