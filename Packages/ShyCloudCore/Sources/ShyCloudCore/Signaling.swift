import Darwin

/// Sends a POSIX signal. Abstracted so tests never signal real processes.
public protocol Signaling: Sendable {
    func send(_ signal: Int32, to pid: Int32) -> Bool
}

public struct DarwinSignaler: Signaling {
    public init() {}

    public func send(_ signal: Int32, to pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, signal) == 0
    }
}
