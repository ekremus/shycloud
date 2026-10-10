import AppKit
import ServiceManagement
import ShyCloudCore
import SwiftUI

struct SettingsView: View {
    let environment: AppEnvironment

    private enum Edge { case start, end }

    @State private var scheduleError = false
    @State private var loginOn = false
    @State private var loginNeedsApproval = false
    @State private var autoUpdate = true

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section {
                StatusHeader(status: environment.sync.status)
            }

            Section {
                DatePicker(String(localized: "Start"), selection: timeBinding(.start), displayedComponents: .hourAndMinute)
                DatePicker(String(localized: "End"), selection: timeBinding(.end), displayedComponents: .hourAndMinute)
            } header: {
                Text("Sync hours")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("iCloud Drive syncs only during these hours and stays paused the rest of the day.")
                    if scheduleError {
                        Text("Start and end can't be the same time.")
                            .foregroundStyle(.red)
                    }
                }
            }

            Section {
                Toggle(isOn: $settings.pausePhotoAnalysis) {
                    Text("Photo analysis")
                    Text("Low risk. Photos still opens normally.")
                }
                Toggle(isOn: $settings.pauseCloudKit) {
                    Text("CloudKit")
                    Text("Also pauses Messages, Notes, Reminders and other iCloud apps. They may freeze until sync resumes.")
                }
                Button(String(localized: "Pause iCloud Photos in the Photos app…")) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Photos.app"))
                }
                .buttonStyle(.link)
            } header: {
                Text("Also pause")
            } footer: {
                Text("While paused, files stored only in iCloud (cloud icon in Finder) open after sync resumes.")
            }

            Section(String(localized: "General")) {
                Toggle(isOn: Binding(
                    get: { loginOn },
                    set: { environment.loginItem.set($0); refresh() }
                )) {
                    Text("Open at login")
                    if loginNeedsApproval {
                        Text("Needs approval in System Settings.")
                    }
                }
                if loginNeedsApproval {
                    Button(String(localized: "Open System Settings…")) { SMAppService.openSystemSettingsLoginItems() }
                }
                Toggle(isOn: $settings.showInMenuBar) {
                    Text("Show in menu bar")
                    if !settings.showInMenuBar {
                        Text("Open ShyCloud again from Applications to return here.")
                    }
                }
                Toggle(String(localized: "Automatically check for updates"), isOn: Binding(
                    get: { autoUpdate },
                    set: { environment.updater.automaticallyChecks = $0; autoUpdate = $0 }
                ))
                Button(String(localized: "Check for Updates…")) { environment.updater.checkForUpdates() }
            }
        }
        .formStyle(.grouped)
        // Fixed size: letting a grouped Form size the window (fixedSize + preferredContentSize)
        // causes an endless update-constraints loop that crashes AppKit. The Form scrolls if needed.
        .frame(width: 440, height: 600)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        loginOn = environment.loginItem.isOn
        loginNeedsApproval = environment.loginItem.status == .requiresApproval
        autoUpdate = environment.updater.automaticallyChecks
        environment.sync.apply()
    }

    private func timeBinding(_ edge: Edge) -> Binding<Date> {
        Binding(
            get: {
                let schedule = environment.settings.schedule
                let clock = edge == .start ? schedule.start : schedule.end
                return Calendar.current.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                let clock = ClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
                let current = environment.settings.schedule
                let proposed = edge == .start
                    ? Schedule(start: clock, end: current.end)
                    : Schedule(start: current.start, end: clock)
                scheduleError = !environment.settings.setSchedule(proposed)
            }
        )
    }
}

/// Live iCloud Drive state at the top of Settings (read-only; the schedule decides it).
private struct StatusHeader: View {
    let status: SyncStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.isPaused ? "icloud.slash" : "icloud")
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(status.isPaused ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(StatusText.settingsHeadline(status))
                    .font(.headline)
                Text(StatusText.settingsDetail(status))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
