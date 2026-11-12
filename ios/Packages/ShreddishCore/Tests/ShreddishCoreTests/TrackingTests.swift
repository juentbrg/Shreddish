import Testing
@testable import ShreddishCore

struct TrackingTests {
    static let lunch = MacroTotals(kcal: 650, proteinG: 50, carbsG: 75, fatG: 17)
    static let dinner = MacroTotals(kcal: 700, proteinG: 50, carbsG: 78, fatG: 23)
    static let breakfast = MacroTotals(kcal: 500, proteinG: 30, carbsG: 60, fatG: 15)
    static let extra = MacroTotals(kcal: 300, proteinG: 5, carbsG: 30, fatG: 18)

    @Test func actualCountsOnlyEatenAndExtras() {
        let log = DayLog(
            day: LocalDay(year: 2026, month: 11, day: 9),
            meals: [
                LoggedMeal(macros: Self.breakfast, status: .planned),
                LoggedMeal(macros: Self.lunch, status: .eaten),
                LoggedMeal(macros: Self.dinner, status: .skipped),
            ],
            extras: [Self.extra]
        )
        let actual = Totals.actual(log)
        #expect(actual.kcal == 950)
        #expect(actual.proteinG == 55)
    }

    static func log(_ day: LocalDay, eaten: Int, total: Int, extras: [MacroTotals] = []) -> DayLog {
        let meals = (0..<total).map { LoggedMeal(macros: Self.lunch, status: $0 < eaten ? .eaten : .skipped) }
        return DayLog(day: day, meals: meals, extras: extras)
    }

    @Test func weeklySummaryUsesElapsedDaysOnly() {
        let start = LocalDay(year: 2026, month: 11, day: 9)
        let days = (0..<7).map { Self.log(start.adding(days: $0), eaten: 4, total: 4) }
        // Mercredi 14 h : lundi et mardi écoulés, mercredi pas encore (avant 21 h).
        let clock = FixedClock(day: start.adding(days: 2), hour: 14)
        let summary = Totals.weeklySummary(days: days, clock: clock)
        #expect(summary.elapsedDays == 2)
        #expect(summary.plannedCount == 8)
        #expect(summary.eatenCount == 8)
        #expect(summary.adherenceRate == 1)
        #expect(summary.averageActual.kcal == 2600)
    }

    @Test func currentDayCountsAfter21h() {
        let start = LocalDay(year: 2026, month: 11, day: 9)
        let days = [Self.log(start, eaten: 2, total: 4), Self.log(start.adding(days: 1), eaten: 1, total: 4)]
        let clock = FixedClock(day: start.adding(days: 1), hour: 21, minute: 0)
        let summary = Totals.weeklySummary(days: days, clock: clock)
        #expect(summary.elapsedDays == 2)
        #expect(summary.eatenCount == 3)
        #expect(summary.plannedCount == 8)
        #expect(summary.adherenceRate == 0.375)
    }

    @Test func averageIncludesExtras() {
        let start = LocalDay(year: 2026, month: 11, day: 9)
        let days = [
            Self.log(start, eaten: 1, total: 1, extras: [Self.extra]),
            Self.log(start.adding(days: 1), eaten: 1, total: 1),
        ]
        let clock = FixedClock(day: start.adding(days: 5))
        let summary = Totals.weeklySummary(days: days, clock: clock)
        #expect(summary.averageActual.kcal == 800) // (950 + 650) / 2
    }

    @Test func noElapsedDayGivesNilAdherence() {
        let start = LocalDay(year: 2026, month: 11, day: 9)
        let clock = FixedClock(day: start, hour: 10)
        let summary = Totals.weeklySummary(days: [Self.log(start, eaten: 0, total: 4)], clock: clock)
        #expect(summary.elapsedDays == 0)
        #expect(summary.adherenceRate == nil)
        #expect(summary.averageActual == .zero)
    }
}
