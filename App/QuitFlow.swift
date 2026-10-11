import AppKit

/// Quit menu item (spec §3.2): always resumes iCloud and exits, no questions.
@MainActor
enum QuitFlow {
    static func run() {
        AppEnvironment.shared.sync.prepareToQuit()
        NSApp.terminate(nil)
    }
}
