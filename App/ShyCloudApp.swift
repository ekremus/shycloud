import SwiftUI

@main
struct ShyCloudApp: App {
    var body: some Scene {
        MenuBarExtra("ShyCloud", systemImage: "icloud") {
            Button("Quit ShyCloud") { NSApp.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}
