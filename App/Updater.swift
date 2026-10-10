import AppKit
import Sparkle

/// Sparkle 2 wrapper. Feed: SUFeedURL in Info.plist.
@MainActor
final class Updater {
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        NSApp.activate() // accessory app: bring Sparkle's window to front
        controller.checkForUpdates(nil)
    }
}
