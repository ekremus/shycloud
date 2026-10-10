import Foundation
import OSLog
import ServiceManagement

/// "Open at login" via SMAppService.mainApp. Registered once on first launch (spec §3.5).
@MainActor
final class LoginItem {
    private let service = SMAppService.mainApp
    private let defaults = UserDefaults.standard
    private let log = Logger(subsystem: "com.ekremus.ShyCloud", category: "LoginItem")

    var status: SMAppService.Status { service.status }
    var isOn: Bool { service.status == .enabled || service.status == .requiresApproval }

    func set(_ on: Bool) {
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            log.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func registerOnFirstLaunch() {
        guard !defaults.bool(forKey: "didRegisterLoginItem") else { return }
        defaults.set(true, forKey: "didRegisterLoginItem")
        set(true)
    }
}
