import ShyCloudCore
import SwiftUI

@main
struct ShyCloudApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Bindable private var settings = AppEnvironment.shared.settings

    var body: some Scene {
        MenuBarExtra(isInserted: $settings.showInMenuBar) {
            MenuContent(environment: .shared)
        } label: {
            MenuBarIcon(sync: AppEnvironment.shared.sync)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarIcon: View {
    let sync: SyncController

    var body: some View {
        Image(StatusText.iconName(sync.status))
            .accessibilityLabel(sync.isPausedNow ? String(localized: "iCloud paused") : String(localized: "iCloud syncing"))
    }
}
