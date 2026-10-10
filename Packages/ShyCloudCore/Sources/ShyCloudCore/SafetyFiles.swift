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

    public func writeHeartbeat(_ date: Date) throws {
        try ensureDirectory()
        try Data(String(date.timeIntervalSince1970).utf8).write(to: heartbeatURL, options: .atomic)
    }

    public func readHeartbeat() -> Date? {
        guard let data = try? Data(contentsOf: heartbeatURL),
              let seconds = Double(String(decoding: data, as: UTF8.self))
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
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

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
