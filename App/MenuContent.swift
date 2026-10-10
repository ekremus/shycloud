import ShyCloudCore
import SwiftUI

/// Classic menu (spec §3.1).
struct MenuContent: View {
    let environment: AppEnvironment

    var body: some View {
        let settings = environment.settings
        Text(StatusText.line(environment.sync.status))
        if let last = settings.lastSyncedAt {
            Text(StatusText.lastSynced(last))
        }
        Divider()
        ForEach(SyncMode.allCases, id: \.self) { mode in
            Toggle(StatusText.title(for: mode, schedule: settings.schedule), isOn: Binding(
                get: { settings.mode == mode },
                set: { if $0 { settings.mode = mode } }
            ))
        }
        Divider()
        Button(String(localized: "Settings…")) { SettingsWindowController.shared.show() }
            .keyboardShortcut(",")
        Button(String(localized: "About ShyCloud")) { AboutPanel.show() }
        Button(String(localized: "Quit ShyCloud")) { QuitFlow.run() }
            .keyboardShortcut("q")
    }
}
