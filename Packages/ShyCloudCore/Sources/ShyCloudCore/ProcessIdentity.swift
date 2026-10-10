/// A process instance: pid plus start time (µs since epoch) so a reused pid never matches.
public struct ProcessIdentity: Codable, Hashable, Sendable {
    public let pid: Int32
    public let startTime: UInt64

    public init(pid: Int32, startTime: UInt64) {
        self.pid = pid
        self.startTime = startTime
    }
}
