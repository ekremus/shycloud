import AppKit

/// Quit menu item (spec §3.2). Only this path asks; all others resume silently.
@MainActor
enum QuitFlow {
    static func run() {
        // Let the menu finish closing before showing a modal alert.
        DispatchQueue.main.async {
            MainActor.assumeIsolated { quit() }
        }
    }

    private static func quit() {
        let environment = AppEnvironment.shared
        var keepPaused = false
        environment.sync.apply() // ask about the current state, not the last tick's
        if environment.sync.isPausedNow {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = String(localized: "Keep iCloud paused after quitting?")
            alert.informativeText = String(localized: "iCloud resumes automatically when you restart or log out.")
            alert.addButton(withTitle: String(localized: "Resume iCloud"))
            alert.addButton(withTitle: String(localized: "Keep Paused"))
            let cancel = alert.addButton(withTitle: String(localized: "Cancel"))
            cancel.keyEquivalent = "\u{1b}"
            let response = alert.runModal()
            if response == .alertThirdButtonReturn { return }
            keepPaused = response == .alertSecondButtonReturn
        }
        environment.sync.prepareToQuit(keepPaused: keepPaused)
        environment.quitHandled = true
        NSApp.terminate(nil)
    }
}
