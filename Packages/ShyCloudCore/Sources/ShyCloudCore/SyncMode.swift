/// What ShyCloud does with iCloud sync.
public enum SyncMode: String, CaseIterable, Codable, Sendable {
    /// Sync always runs.
    case alwaysSync
    /// Sync always paused (vacation/sleep mode).
    case alwaysPause
    /// Sync runs only inside the daily window.
    case scheduled
}
