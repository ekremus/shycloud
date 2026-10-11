import Foundation
import OSLog
import ShyCloudCore

// ShyCloud safety helper. launchd runs this every 60 s (see the LaunchAgent plist).
// If ShyCloud stopped heartbeating (crash, force quit), nobody is letting iCloud breathe any more,
// so resume it.

let files = SafetyFiles.standard
let inspector = DarwinProcessInspector()

// Proof of life for the app: SMAppService status alone can be stale (spec §5.5/5.7).
try? files.writeWatchdogRan(Date())

if WatchdogDecision.decide(heartbeat: files.readHeartbeat(), now: Date()) == .resume {
    // Log only real resumes; after a normal quit this branch runs every minute with nothing stopped.
    let anyStopped = PauseTarget.allCases.contains { inspector.processes(for: $0).contains(where: inspector.isStopped) }
    if anyStopped {
        Logger(subsystem: "com.ekremus.ShyCloud", category: "Watchdog")
            .notice("Resuming iCloud: stale heartbeat")
    }
    SignalProcessController(inspector: inspector, watchExits: false).resumeAll()
}
