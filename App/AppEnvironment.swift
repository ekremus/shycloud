import AppKit
import ShyCloudCore

/// Object graph and timers. Created lazily on first access; `start()` runs once at launch.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let settings: AppSettings
    let safetyHelper: SafetyHelper
    let loginItem: LoginItem
    let updater: Updater
    private(set) lazy var sync: SyncController = SyncController(
        settings: settings,
        processes: SignalProcessController(),
        files: .standard,
        activity: ProcessActivityHolder(),
        probe: UbiquityProbe(),
        makeTimer: { DispatchOneShotTimer(leeway: $0) },
        // Registered is not enough: the watchdog must also have actually run recently.
        helperState: { [unowned self] in self.helperState }
    )

    private var tickTimer: Timer?
    private var started = false

    private init() {
        let settings = AppSettings()
        let helper = SafetyHelper()
        self.settings = settings
        self.safetyHelper = helper
        self.loginItem = LoginItem()
        self.updater = Updater()
    }

    /// Not enabled: `.disabled`. Enabled but the watchdog hasn't run recently (fresh install, or launchd skipped
    /// its runs during sleep): `.starting`. Otherwise `.working` (see `WatchdogDecision`).
    var helperState: SafetyHelperState {
        guard safetyHelper.isEnabled else { return .disabled }
        let alive = WatchdogDecision.isWatchdogAlive(lastRun: SafetyFiles.standard.readWatchdogRan(), now: Date())
        return alive ? .working : .starting
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
