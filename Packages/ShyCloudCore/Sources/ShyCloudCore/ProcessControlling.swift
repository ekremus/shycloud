/// Pauses and resumes pause targets. The only abstraction that touches other processes.
@MainActor
public protocol ProcessControlling: AnyObject {
    /// Called when a process ShyCloud paused exits (e.g. launchd replaced it).
    var onPausedProcessExit: (@MainActor () -> Void)? { get set }
    func pause(_ targets: [PauseTarget])
    func resume(_ targets: [PauseTarget])
    /// Processes ShyCloud paused that are still alive and stopped.
    func pausedProcesses() -> [ProcessIdentity]
}

public extension ProcessControlling {
    func resumeAll() {
        resume(PauseTarget.allCases)
    }
}
