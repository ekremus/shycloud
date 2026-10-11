import AppKit
import SwiftUI

/// Hosts AboutView in one reusable NSWindow (spec §3.4). Mirrors SettingsWindowController.
@MainActor
final class AboutWindowController {
    static let shared = AboutWindowController()
    private static let size = NSSize(width: 300, height: 360)
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: AboutView())
            // No size negotiation between SwiftUI and the window: both are fixed at the same size.
            hosting.sizingOptions = []
            let window = AboutWindow(
                contentRect: NSRect(origin: .zero, size: Self.size),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hosting
            window.setContentSize(Self.size)
            window.title = String(localized: "About shyCloud")
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

/// Closes with Esc and ⌘W (an accessory app has no File menu to provide ⌘W).
private final class AboutWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
