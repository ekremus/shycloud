import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sigtermSource: (any DispatchSourceSignal)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SIGTERM would bypass applicationWillTerminate; route it through terminate (spec §3.2).
        // Installed before start() so a SIGTERM right after the first pause still resumes.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        source.resume()
        sigtermSource = source
        AppEnvironment.shared.start()
    }

    /// Opening the app again (Finder/Spotlight) shows Settings — the way back when the icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    /// Every termination resumes iCloud (spec §3.2). Idempotent after the Quit menu item.
    func applicationWillTerminate(_ notification: Notification) {
        AppEnvironment.shared.sync.prepareToQuit()
    }
}
