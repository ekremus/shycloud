import Foundation
import Observation

/// User settings persisted in UserDefaults.
@MainActor
@Observable
public final class AppSettings {
    private enum Key {
        static let mode = "mode"
        static let startHour = "startHour"
        static let startMinute = "startMinute"
        static let endHour = "endHour"
        static let endMinute = "endMinute"
        static let pausePhotoAnalysis = "pausePhotoAnalysis"
        static let pauseCloudKit = "pauseCloudKit"
        static let showInMenuBar = "showInMenuBar"
        static let lastSyncedAt = "lastSyncedAt"
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// Fires after mode, schedule or target changes. Not for showInMenuBar / lastSyncedAt.
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?

    public var mode: SyncMode {
        didSet { defaults.set(mode.rawValue, forKey: Key.mode); onChange?() }
    }

    public private(set) var schedule: Schedule

    public var pausePhotoAnalysis: Bool {
        didSet { defaults.set(pausePhotoAnalysis, forKey: Key.pausePhotoAnalysis); onChange?() }
    }

    public var pauseCloudKit: Bool {
        didSet { defaults.set(pauseCloudKit, forKey: Key.pauseCloudKit); onChange?() }
    }

    public var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: Key.showInMenuBar) }
    }

    public var lastSyncedAt: Date? {
        didSet { defaults.set(lastSyncedAt, forKey: Key.lastSyncedAt) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Key.mode).flatMap(SyncMode.init(rawValue:)) ?? .scheduled
        let fallback = Schedule.default
        func clock(_ hourKey: String, _ minuteKey: String, _ backup: ClockTime) -> ClockTime {
            let hour = defaults.object(forKey: hourKey) as? Int ?? backup.hour
            let minute = defaults.object(forKey: minuteKey) as? Int ?? backup.minute
            // Hand-edited out-of-range values fall back instead of crashing.
            guard (0..<24).contains(hour), (0..<60).contains(minute) else { return backup }
            return ClockTime(hour: hour, minute: minute)
        }
        let stored = Schedule(
            start: clock(Key.startHour, Key.startMinute, fallback.start),
            end: clock(Key.endHour, Key.endMinute, fallback.end)
        )
        schedule = stored.isValid ? stored : fallback
        pausePhotoAnalysis = defaults.bool(forKey: Key.pausePhotoAnalysis)
        pauseCloudKit = defaults.bool(forKey: Key.pauseCloudKit)
        showInMenuBar = defaults.object(forKey: Key.showInMenuBar) as? Bool ?? true
        lastSyncedAt = defaults.object(forKey: Key.lastSyncedAt) as? Date
    }

    /// Returns false (and keeps the old value) when start == end.
    @discardableResult
    public func setSchedule(_ newValue: Schedule) -> Bool {
        guard newValue.isValid else { return false }
        schedule = newValue
        defaults.set(newValue.start.hour, forKey: Key.startHour)
        defaults.set(newValue.start.minute, forKey: Key.startMinute)
        defaults.set(newValue.end.hour, forKey: Key.endHour)
        defaults.set(newValue.end.minute, forKey: Key.endMinute)
        onChange?()
        return true
    }

    /// Targets to pause, in pause order. iCloud Drive is always included.
    public var enabledTargets: [PauseTarget] {
        PauseTarget.pauseOrder.filter { target in
            switch target {
            case .drive: true
            case .photoAnalysis: pausePhotoAnalysis
            case .cloudKit: pauseCloudKit
            }
        }
    }
}
