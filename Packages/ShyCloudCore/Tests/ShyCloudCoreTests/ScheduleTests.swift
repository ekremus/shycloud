import Foundation
import Testing
@testable import ShyCloudCore

struct ScheduleTests {
    let night = Schedule(start: ClockTime(hour: 2, minute: 0), end: ClockTime(hour: 9, minute: 0))
    let evening = Schedule(start: ClockTime(hour: 22, minute: 0), end: ClockTime(hour: 6, minute: 30))
    let cal = TestTime.calendar()

    @Test func defaultIsTwoToNine() {
        #expect(Schedule.default == night)
    }

    @Test func insideAndOutsideSameDayWindow() {
        #expect(night.isInside(TestTime.date("2026-10-12 03:00"), calendar: cal))
        #expect(!night.isInside(TestTime.date("2026-10-12 14:00"), calendar: cal))
        #expect(!night.isInside(TestTime.date("2026-10-12 01:59"), calendar: cal))
    }

    @Test func boundariesStartInclusiveEndExclusive() {
        #expect(night.isInside(TestTime.date("2026-10-12 02:00"), calendar: cal))
        #expect(!night.isInside(TestTime.date("2026-10-12 09:00"), calendar: cal))
        #expect(night.isInside(TestTime.date("2026-10-12 08:59"), calendar: cal))
    }

    @Test func windowCrossingMidnight() {
        #expect(evening.isInside(TestTime.date("2026-10-12 23:30"), calendar: cal))
        #expect(evening.isInside(TestTime.date("2026-10-13 05:00"), calendar: cal))
        #expect(!evening.isInside(TestTime.date("2026-10-13 06:30"), calendar: cal))
        #expect(!evening.isInside(TestTime.date("2026-10-12 12:00"), calendar: cal))
    }

    @Test func nextChangeOutsideIsNextStart() {
        let next = night.nextChange(after: TestTime.date("2026-10-12 14:00"), calendar: cal)
        #expect(next == TestTime.date("2026-10-13 02:00"))
    }

    @Test func nextChangeInsideIsEnd() {
        let next = night.nextChange(after: TestTime.date("2026-10-12 03:00"), calendar: cal)
        #expect(next == TestTime.date("2026-10-12 09:00"))
    }

    @Test func nextChangeExactlyAtEndIsNextStart() {
        let next = night.nextChange(after: TestTime.date("2026-10-12 09:00"), calendar: cal)
        #expect(next == TestTime.date("2026-10-13 02:00"))
    }

    @Test func nextChangeCrossingMidnight() {
        let next = evening.nextChange(after: TestTime.date("2026-10-12 23:00"), calendar: cal)
        #expect(next == TestTime.date("2026-10-13 06:30"))
    }

    @Test func springForwardGapStartsAtThree() {
        // 2026-03-08 02:00 does not exist in New York; clocks jump to 03:00 EDT (07:00 UTC).
        let ny = TestTime.calendar(TestTime.newYork)
        let before = TestTime.date("2026-03-08 01:30", TestTime.newYork)
        let next = night.nextChange(after: before, calendar: ny)
        #expect(next == Date(timeIntervalSince1970: 1_772_953_200)) // 2026-03-08T07:00:00Z
        #expect(night.isInside(next, calendar: ny))
    }

    @Test func fallBackUsesFirstOccurrence() {
        // 2026-11-01: 01:00–02:00 repeats in New York. 02:00 EST = 07:00 UTC.
        let ny = TestTime.calendar(TestTime.newYork)
        let before = TestTime.date("2026-11-01 00:30", TestTime.newYork)
        let next = night.nextChange(after: before, calendar: ny)
        #expect(next == Date(timeIntervalSince1970: 1_793_516_400)) // 2026-11-01T07:00:00Z
    }

    @Test func validity() {
        #expect(night.isValid)
        #expect(!Schedule(start: ClockTime(hour: 5, minute: 0), end: ClockTime(hour: 5, minute: 0)).isValid)
    }
}
