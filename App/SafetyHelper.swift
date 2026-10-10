import OSLog
import ServiceManagement

/// The watchdog LaunchAgent (spec §4). Registered on every launch.
@MainActor
final class SafetyHelper {
    private let service = SMAppService.agent(plistName: "com.ekremus.ShyCloud.Watchdog.plist")
    private let log = Logger(subsystem: "com.ekremus.ShyCloud", category: "SafetyHelper")

    var status: SMAppService.Status { service.status }
    var isEnabled: Bool { service.status == .enabled }

    func register() {
        guard service.status != .enabled else { return }
        do {
            try service.register()
        } catch {
            log.error("Watchdog registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
