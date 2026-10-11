/// A system process ShyCloud may pause. Matched only by exact absolute executable path.
public enum PauseTarget: String, CaseIterable, Codable, Sendable {
    /// iCloud Drive sync engine (`bird`). Always paused when sync is paused.
    case drive
    /// iCloud Photos sync (`cloudphotod`). Optional. The Photos app still opens.
    case photos
    /// Photo analysis (`photoanalysisd`). Optional, low risk.
    case photoAnalysis
    /// CloudKit (`cloudd`). Optional, advanced: affects Messages, Notes, Reminders and more.
    case cloudKit

    public static let pauseOrder: [PauseTarget] = [.drive, .photos, .photoAnalysis, .cloudKit]
    public static let resumeOrder: [PauseTarget] = pauseOrder.reversed()

    /// Known install locations across macOS 26–27. Simulator runtimes live under
    /// /Library/Developer/CoreSimulator and must never match.
    public var executablePaths: Set<String> {
        switch self {
        case .drive:
            [
                "/System/Library/PrivateFrameworks/iCloudDriveCore.framework/Versions/A/Support/bird",
                "/System/Library/PrivateFrameworks/CloudDocsDaemon.framework/Versions/A/Support/bird",
            ]
        case .photos:
            [
                "/System/Library/PrivateFrameworks/CloudPhotoLibrary.framework/Versions/A/Support/cloudphotod",
            ]
        case .photoAnalysis:
            [
                "/System/Library/PrivateFrameworks/PhotoAnalysis.framework/Versions/A/Support/photoanalysisd",
                "/System/Library/PrivateFrameworks/PhotoAnalysis.framework/Support/photoanalysisd",
            ]
        case .cloudKit:
            [
                "/System/Library/PrivateFrameworks/CloudKitDaemon.framework/Support/cloudd",
                "/System/Library/PrivateFrameworks/CloudKitDaemon.framework/Versions/A/Support/cloudd",
            ]
        }
    }

    public static func target(forExecutablePath path: String) -> PauseTarget? {
        allCases.first { $0.executablePaths.contains(path) }
    }
}
