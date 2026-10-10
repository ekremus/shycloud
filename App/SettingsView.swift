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
    @State private var helperEnabled = true
    @State private var autoUpdate = true

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section(String(localized: "Sync window")) {
                DatePicker(String(localized: "Start"), selection: timeBinding(.start), displayedComponents: .hourAndMinute)
                DatePicker(String(localized: "End"), selection: timeBinding(.end), displayedComponents: .hourAndMinute)
                if scheduleError {
                    Text("Start and end can't be the same time.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section(String(localized: "What to pause")) {
                Toggle(String(localized: "iCloud Drive"), isOn: .constant(true))
                    .disabled(true)
                Toggle(String(localized: "Photo analysis"), isOn: $settings.pausePhotoAnalysis)
                Button(String(localized: "Pause iCloud Photos in the Photos app…")) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Photos.app"))
                }
                .buttonStyle(.link)
            }

            Section(String(localized: "Advanced")) {
                Toggle(String(localized: "CloudKit"), isOn: $settings.pauseCloudKit)
                Text("Also pauses Messages, Notes, Reminders and other apps that sync with iCloud. Those apps may freeze until sync resumes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "General")) {
                Toggle(String(localized: "Open at login"), isOn: Binding(
                    get: { loginOn },
                    set: { environment.loginItem.set($0); refresh() }
                ))
                if loginNeedsApproval {
                    HStack {
                        Text("Needs approval in System Settings.")
                        Button(String(localized: "Open System Settings…")) { SMAppService.openSystemSettingsLoginItems() }
                    }
                    .font(.caption)
                }
                Toggle(String(localized: "Show in menu bar"), isOn: $settings.showInMenuBar)
                if !settings.showInMenuBar {
                    Text("Open ShyCloud again from Applications to return here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle(String(localized: "Automatically check for updates"), isOn: Binding(
                    get: { autoUpdate },
                    set: { environment.updater.automaticallyChecks = $0; autoUpdate = $0 }
                ))
                Button(String(localized: "Check for Updates…")) { environment.updater.checkForUpdates() }
            }

            Section(String(localized: "Safety helper")) {
                if helperEnabled {
                    Label(String(localized: "On — resumes iCloud if ShyCloud ever stops unexpectedly."), systemImage: "checkmark.shield")
                } else {
                    Text("Safety helper is disabled in System Settings › General › Login Items & Extensions. ShyCloud won't pause iCloud until it is enabled.")
                        .foregroundStyle(.orange)
                    Button(String(localized: "Open System Settings…")) { environment.safetyHelper.openSystemSettings() }
                }
            }

            Text("While paused, files stored only in iCloud (cloud icon in Finder) can't open until sync runs.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        loginOn = environment.loginItem.isOn
        loginNeedsApproval = environment.loginItem.status == .requiresApproval
        helperEnabled = environment.safetyHelper.isEnabled
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
