import Foundation
import Testing
@testable import ShyCloudCore

@MainActor
struct AppSettingsTests {
    func freshDefaults() -> UserDefaults {
        let name = "shycloud-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaults() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.mode == .scheduled)
        #expect(settings.schedule == .default)
        #expect(!settings.pausePhotos)
        #expect(!settings.pausePhotoAnalysis)
        #expect(!settings.pauseCloudKit)
        #expect(!settings.stopUploadsCompletely)
        #expect(settings.showInMenuBar)
        #expect(settings.lastSyncedAt == nil)
        #expect(settings.enabledTargets == [.drive])
    }

    @Test func persistsAcrossInstances() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.mode = .alwaysPause
        first.setSchedule(Schedule(start: ClockTime(hour: 22, minute: 15), end: ClockTime(hour: 6, minute: 0)))
        first.pausePhotos = true
        first.pauseCloudKit = true
        first.stopUploadsCompletely = true
        first.showInMenuBar = false
        first.lastSyncedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let second = AppSettings(defaults: defaults)
        #expect(second.mode == .alwaysPause)
        #expect(second.schedule == Schedule(start: ClockTime(hour: 22, minute: 15), end: ClockTime(hour: 6, minute: 0)))
        #expect(second.pausePhotos)
        #expect(second.pauseCloudKit)
        #expect(second.stopUploadsCompletely)
        #expect(!second.showInMenuBar)
        #expect(second.lastSyncedAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(second.enabledTargets == [.drive, .photos, .cloudKit])
    }

    @Test func rejectsInvalidSchedule() {
        let settings = AppSettings(defaults: freshDefaults())
        let ok = settings.setSchedule(Schedule(start: ClockTime(hour: 5, minute: 0), end: ClockTime(hour: 5, minute: 0)))
        #expect(!ok)
        #expect(settings.schedule == .default)
    }

    @Test func onChangeFiresForBehaviourSettingsOnly() {
        let settings = AppSettings(defaults: freshDefaults())
        var count = 0
        settings.onChange = { count += 1 }
        settings.mode = .alwaysSync
        settings.pausePhotos = true
        settings.pausePhotoAnalysis = true
        settings.pauseCloudKit = true
        settings.stopUploadsCompletely = true
        settings.setSchedule(Schedule(start: ClockTime(hour: 1, minute: 0), end: ClockTime(hour: 2, minute: 0)))
        #expect(count == 6)
        settings.showInMenuBar = false
        settings.lastSyncedAt = .now
        #expect(count == 6)
    }

    @Test func stopUploadsCompletelyUsesItsOwnKey() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "stopUploadsCompletely")
        #expect(AppSettings(defaults: defaults).stopUploadsCompletely)
    }

    @Test func outOfRangeStoredTimeFallsBack() {
        let defaults = freshDefaults()
        defaults.set(25, forKey: "startHour")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.schedule == .default)
    }

    @Test func enabledTargetsFollowPauseOrder() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.pauseCloudKit = true
        settings.pausePhotoAnalysis = true
        settings.pausePhotos = true
        #expect(settings.enabledTargets == [.drive, .photos, .photoAnalysis, .cloudKit])
    }
}
