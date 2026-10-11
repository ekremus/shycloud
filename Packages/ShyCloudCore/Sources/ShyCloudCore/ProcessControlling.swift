/// Pauses and resumes pause targets. The only abstraction that touches other processes.
@MainActor
public protocol ProcessControlling: AnyObject {
    /// Called when a process ShyCloud paused exits (e.g. launchd replaced it).
    var onPausedProcessExit: (@MainActor () -> Void)? { get set }
    func pause(_ targets: [PauseTarget])
    func resume(_ targets: [PauseTarget])
    /// Breath (see `Breather`): continue the processes ShyCloud paused, still owning them.
    func releaseForBreath()
    /// End of a breath: stop the processes released by `releaseForBreath` again.
    func restopAfterBreath()
}

public extension ProcessControlling {
    func resumeAll() {
        resume(PauseTarget.allCases)
    }
}
