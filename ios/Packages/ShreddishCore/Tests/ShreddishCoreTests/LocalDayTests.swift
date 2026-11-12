import Foundation
import Testing
@testable import ShreddishCore

struct LocalDayTests {
    @Test func keyRoundTrip() {
        let day = LocalDay(year: 2026, month: 11, day: 11)
        #expect(day.key == 20_261_111)
        #expect(LocalDay(key: day.key) == day)
    }

    @Test func addingDaysCrossesMonthAndYear() {
        #expect(LocalDay(year: 2026, month: 12, day: 28).adding(days: 6) == LocalDay(year: 2027, month: 1, day: 3))
        #expect(LocalDay(year: 2028, month: 2, day: 28).adding(days: 1) == LocalDay(year: 2028, month: 2, day: 29))
        #expect(LocalDay(year: 2026, month: 3, day: 1).adding(days: -1) == LocalDay(year: 2026, month: 2, day: 28))
    }

    @Test func daysSince() {
        let start = LocalDay(year: 2026, month: 10, day: 20)
        #expect(LocalDay(year: 2026, month: 11, day: 3).days(since: start) == 14)
    }

    @Test func dstChangeDoesNotShiftDays() {
        // Passage à l'heure d'hiver à Paris le 25 octobre 2026.
        let day = LocalDay(year: 2026, month: 10, day: 24)
        #expect(day.adding(days: 1) == LocalDay(year: 2026, month: 10, day: 25))
        #expect(day.adding(days: 2) == LocalDay(year: 2026, month: 10, day: 26))
    }

    @Test func fixedClockToday() {
        let clock = FixedClock(day: LocalDay(year: 2026, month: 11, day: 11), hour: 23, minute: 30)
        #expect(clock.today == LocalDay(year: 2026, month: 11, day: 11))
        #expect(clock.minuteOfDay == 23 * 60 + 30)
    }

    @Test func dateRoundTrip() {
        let clock = FixedClock(day: LocalDay(year: 2026, month: 11, day: 11))
        let day = LocalDay(year: 2026, month: 11, day: 15)
        #expect(LocalDay(date: day.startDate(calendar: clock.calendar), calendar: clock.calendar) == day)
    }
}
