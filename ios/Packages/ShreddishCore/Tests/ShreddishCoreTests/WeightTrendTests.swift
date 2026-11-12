import Testing
@testable import ShreddishCore

struct WeightTrendTests {
    static let start = LocalDay(year: 2026, month: 11, day: 2)

    static func point(_ offset: Int, _ weight: Double) -> WeightPoint {
        WeightPoint(day: start.adding(days: offset), weightKg: weight)
    }

    @Test func lessThanTwoWeeksGivesNil() {
        #expect(WeightTrend.weeklyLossRate([Self.point(0, 82), Self.point(13, 80)]) == nil)
        #expect(WeightTrend.weeklyLossRate([Self.point(0, 82)]) == nil)
        #expect(WeightTrend.weeklyLossRate([]) == nil)
    }

    @Test func quickstartScenarioIsTooFast() throws {
        // 82 → 80 kg en 2 semaines : 1,22 % / semaine.
        let entries = [Self.point(0, 82), Self.point(7, 81), Self.point(14, 80)]
        let rate = try #require(WeightTrend.weeklyLossRate(entries))
        #expect(abs(rate - 1.2195) < 0.001)
        #expect(WeightTrend.isTooFast(entries, goal: .cut))
    }

    @Test func alertOnlyWhenCutting() {
        let entries = [Self.point(0, 82), Self.point(14, 80)]
        #expect(!WeightTrend.isTooFast(entries, goal: .recomp))
        #expect(!WeightTrend.isTooFast(entries, goal: .bulk))
    }

    @Test func onePercentIsNotTooFast() {
        // 80 → 78,4 en 2 semaines : exactement 1 % / semaine.
        let entries = [Self.point(0, 80), Self.point(14, 78.4)]
        #expect(!WeightTrend.isTooFast(entries, goal: .cut))
    }

    @Test func usesClosestReferenceAtLeastTwoWeeksBefore() throws {
        // Référence : 13 nov (17 jours avant), pas 2 nov.
        let entries = [Self.point(0, 90), Self.point(11, 82), Self.point(28, 80), Self.point(20, 81)]
        let rate = try #require(WeightTrend.weeklyLossRate(entries))
        #expect(abs(rate - (2.0 / 82 * 100) / (17.0 / 7)) < 0.001)
    }

    @Test func gainGivesNegativeRate() throws {
        let rate = try #require(WeightTrend.weeklyLossRate([Self.point(0, 70), Self.point(14, 71)]))
        #expect(rate < 0)
    }
}
