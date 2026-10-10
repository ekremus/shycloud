import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sigtermSource: (any DispatchSourceSignal)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppEnvironment.shared.start()
        // SIGTERM would bypass applicationWillTerminate; route it through terminate (spec §3.2).
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        source.resume()
        sigtermSource = source
    }

    /// Opening the app again (Finder/Spotlight) shows Settings — the way back when the icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    /// Every termination except Quit + "Keep Paused" resumes iCloud (spec §3.2).
    func applicationWillTerminate(_ notification: Notification) {
        let environment = AppEnvironment.shared
        if !environment.quitHandled {
            environment.sync.prepareToQuit(keepPaused: false)
        }
    }
}
