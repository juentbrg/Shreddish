import Testing
@testable import ShreddishCore

struct TotalsTests {
    @Test func plannedSumsMeals() throws {
        let day = try Fixture.week().days[0]
        let totals = Totals.planned(day.meals)
        #expect(totals.kcal == 2208)
        #expect(totals.proteinG == 160)
        #expect(totals.carbsG == 248)
        #expect(totals.fatG == 64)
    }

    @Test func deviationIsSignedRatio() {
        let over = MacroTotals(kcal: 2427.7, proteinG: 0, carbsG: 0, fatG: 0)
        #expect(abs(Totals.deviation(over, targetKcal: 2207) - 0.1) < 0.001)
        let under = MacroTotals(kcal: 1986.3, proteinG: 0, carbsG: 0, fatG: 0)
        #expect(abs(Totals.deviation(under, targetKcal: 2207) + 0.1) < 0.001)
    }

    @Test func offTargetBeyondTenPercent() {
        #expect(Totals.isOffTarget(0.11))
        #expect(Totals.isOffTarget(-0.11))
        #expect(!Totals.isOffTarget(0.10))
        #expect(!Totals.isOffTarget(-0.05))
    }

    @Test func deviationWithZeroTargetIsZero() {
        #expect(Totals.deviation(.zero, targetKcal: 0) == 0)
    }
}
