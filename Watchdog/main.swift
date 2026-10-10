import Foundation
import OSLog
import ShyCloudCore

// ShyCloud safety helper. launchd runs this every 60 s (see the LaunchAgent plist).
// If ShyCloud stopped heartbeating (crash, force quit), resume iCloud — unless the user
// explicitly chose "Keep Paused" and those exact processes are still stopped.

let files = SafetyFiles.standard
let inspector = DarwinProcessInspector()

// Proof of life for the app: SMAppService status alone can be stale (spec §5.5/5.7).
try? files.writeWatchdogRan(Date())

let keepPaused = files.readKeepPaused()
let action = WatchdogDecision.decide(
    heartbeat: files.readHeartbeat(),
    now: Date(),
    keepPaused: keepPaused,
    isAliveAndStopped: { id in inspector.target(of: id) != nil && inspector.isStopped(id) }
)

if action == .resume {
    // Log only real resumes; after a normal quit this branch runs every minute with nothing stopped.
    let anyStopped = PauseTarget.allCases.contains { inspector.processes(for: $0).contains(where: inspector.isStopped) }
    if anyStopped {
        let reason = keepPaused?.isEmpty == false ? "stale keep-paused" : "stale heartbeat"
        Logger(subsystem: "com.ekremus.ShyCloud", category: "Watchdog")
            .notice("Resuming iCloud: \(reason, privacy: .public)")
    }
    files.deleteKeepPaused()
    SignalProcessController(inspector: inspector, watchExits: false).resumeAll()
}
