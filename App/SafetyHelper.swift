import Foundation
import OSLog
import ServiceManagement

/// The watchdog LaunchAgent (spec §4). Registered on every launch.
@MainActor
final class SafetyHelper {
    private static let registeredPathKey = "watchdogRegisteredPath"

    private let service = SMAppService.agent(plistName: "com.ekremus.ShyCloud.Watchdog.plist")
    private let defaults = UserDefaults.standard
    private let log = Logger(subsystem: "com.ekremus.ShyCloud", category: "SafetyHelper")

    var status: SMAppService.Status { service.status }
    var isEnabled: Bool { service.status == .enabled }

    /// Re-registers when the app moved since the last registration (e.g. first launch from a
    /// translocated DMG path, then from /Applications): the old registration points at a dead path.
    func register() {
        let path = Bundle.main.bundlePath
        if service.status == .enabled {
            guard defaults.string(forKey: Self.registeredPathKey) != path else { return }
            do {
                try service.unregister()
            } catch {
                log.error("Watchdog unregistration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        do {
            try service.register()
            defaults.set(path, forKey: Self.registeredPathKey)
        } catch {
            log.error("Watchdog registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
