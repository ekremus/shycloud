import AppKit
import ShyCloudCore

/// Object graph and timers. Created lazily on first access; `start()` runs once at launch.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let settings: AppSettings
    let safetyHelper: SafetyHelper
    let loginItem: LoginItem
    let sync: SyncController
    var quitHandled = false

    private var tickTimer: Timer?
    private var started = false

    private init() {
        let settings = AppSettings()
        let helper = SafetyHelper()
        self.settings = settings
        self.safetyHelper = helper
        self.loginItem = LoginItem()
        self.sync = SyncController(
            settings: settings,
            processes: SignalProcessController(),
            files: .standard,
            activity: ProcessActivityHolder(),
            isHelperEnabled: { helper.isEnabled }
        )
    }

    func start() {
        guard !started else { return }
        started = true
        sync.start(registerHelper: { [safetyHelper, loginItem] in
            safetyHelper.register()
            loginItem.registerOnFirstLaunch()
        })
        let timer = Timer(timeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { AppEnvironment.shared.sync.tick() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        SystemEvents.observe(sync)
    }
}
