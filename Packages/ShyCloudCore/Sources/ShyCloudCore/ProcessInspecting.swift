/// Read-only view of running processes.
public protocol ProcessInspecting: Sendable {
    /// Live instances of `target` owned by the current user.
    func processes(for target: PauseTarget) -> [ProcessIdentity]
    /// The target `id` still is: alive, same start time, allowlisted path, current user. Otherwise nil.
    func target(of id: ProcessIdentity) -> PauseTarget?
    /// True when `id` is alive with the same start time and in the stopped (SSTOP) state.
    func isStopped(_ id: ProcessIdentity) -> Bool
}
