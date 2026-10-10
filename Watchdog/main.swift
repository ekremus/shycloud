import Foundation
import ShyCloudCore

// ShyCloud safety helper. launchd runs this every 60 s (see the LaunchAgent plist).
// If ShyCloud stopped heartbeating (crash, force quit), resume iCloud — unless the user
// explicitly chose "Keep Paused" and those exact processes are still stopped.

let files = SafetyFiles.standard
let inspector = DarwinProcessInspector()

let action = WatchdogDecision.decide(
    heartbeat: files.readHeartbeat(),
    now: Date(),
    keepPaused: files.readKeepPaused(),
    isAliveAndStopped: { id in inspector.target(of: id) != nil && inspector.isStopped(id) }
)

if action == .resume {
    files.deleteKeepPaused()
    SignalProcessController(inspector: inspector, watchExits: false).resumeAll()
}
