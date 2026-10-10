import Foundation

/// Files shared between the app and the watchdog.
public struct SafetyFiles: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var standard: SafetyFiles {
        SafetyFiles(directory: URL.homeDirectory.appending(path: "Library/Application Support/ShyCloud", directoryHint: .isDirectory))
    }

    var heartbeatURL: URL { directory.appending(path: "heartbeat") }
    var keepPausedURL: URL { directory.appending(path: "keep-paused.json") }
    var watchdogRanURL: URL { directory.appending(path: "watchdog-ran") }

    public func writeHeartbeat(_ date: Date) throws {
        try writeDate(date, to: heartbeatURL)
    }

    public func readHeartbeat() -> Date? {
        readDate(at: heartbeatURL)
    }

    /// Written by the watchdog at the start of every run, so the app can tell it is really alive.
    public func writeWatchdogRan(_ date: Date) throws {
        try writeDate(date, to: watchdogRanURL)
    }

    public func readWatchdogRan() -> Date? {
        readDate(at: watchdogRanURL)
    }

    public func writeKeepPaused(_ ids: [ProcessIdentity]) throws {
        try ensureDirectory()
        try JSONEncoder().encode(ids).write(to: keepPausedURL, options: .atomic)
    }

    public func readKeepPaused() -> [ProcessIdentity]? {
        guard let data = try? Data(contentsOf: keepPausedURL) else { return nil }
        return try? JSONDecoder().decode([ProcessIdentity].self, from: data)
    }

    public func deleteKeepPaused() {
        try? FileManager.default.removeItem(at: keepPausedURL)
    }

    private func writeDate(_ date: Date, to url: URL) throws {
        try ensureDirectory()
        try Data(String(date.timeIntervalSince1970).utf8).write(to: url, options: .atomic)
    }

    /// Fail-safe: missing, garbage or non-finite contents read as nil.
    private func readDate(at url: URL) -> Date? {
        guard let data = try? Data(contentsOf: url),
              let seconds = Double(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
              seconds.isFinite
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
