import Darwin

/// `libproc`-based inspector. Matches by exact path and uid, never by name.
public struct DarwinProcessInspector: ProcessInspecting {
    /// `SSTOP` from <sys/proc.h>.
    static let statusStopped: UInt32 = 4

    private let uid: uid_t

    public init(uid: uid_t = getuid()) {
        self.uid = uid
    }

    public func processes(for target: PauseTarget) -> [ProcessIdentity] {
        allPIDs().compactMap { pid in
            guard let id = identity(of: pid), self.target(of: id) == target else { return nil }
            return id
        }
    }

    public func target(of id: ProcessIdentity) -> PauseTarget? {
        guard let info = bsdInfo(id.pid),
              info.pbi_uid == uid,
              startTime(of: info) == id.startTime,
              let path = path(of: id.pid)
        else { return nil }
        return PauseTarget.target(forExecutablePath: path)
    }

    public func isStopped(_ id: ProcessIdentity) -> Bool {
        guard let info = bsdInfo(id.pid), startTime(of: info) == id.startTime else { return false }
        return info.pbi_status == Self.statusStopped
    }

    public func identity(of pid: Int32) -> ProcessIdentity? {
        bsdInfo(pid).map { ProcessIdentity(pid: pid, startTime: startTime(of: $0)) }
    }

    private func startTime(of info: proc_bsdinfo) -> UInt64 {
        info.pbi_start_tvsec &* 1_000_000 &+ info.pbi_start_tvusec
    }

    private func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return pids.prefix(Int(count)).filter { $0 > 0 }
    }

    private func path(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBytes { raw in
            proc_pidpath(pid, raw.baseAddress, UInt32(raw.count))
        }
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    private func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, size)
        }
        return result == size ? info : nil
    }
}
