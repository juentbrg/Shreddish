import Testing
@testable import ShreddishCore

struct BudgetValidationTests {
    // Coût fixture : 8,20 € / jour, 57,40 € / semaine.

    @Test func weekAboveCeilingIsFatal() throws {
        let result = AIOutputValidator.validate(
            week: try Fixture.week(), constraints: constraints(weeklyBudgetEur: 56, budgetTolerance: 0)
        )
        #expect(result.sanitized == nil)
        #expect(result.fatal.contains { if case .weekOverBudget = $0 { true } else { false } })
    }

    @Test func weekWithinToleranceIsAcceptedAndFlagged() throws {
        // Plafond 56 × 1,05 = 58,80 €.
        let result = AIOutputValidator.validate(
            week: try Fixture.week(), constraints: constraints(weeklyBudgetEur: 56, budgetTolerance: 0.05)
        )
        #expect(result.isValid)
        #expect(result.warnings.contains { if case .weekOverBudgetWithinTolerance = $0 { true } else { false } })
    }

    @Test func weekUnderBudgetIsSilent() throws {
        let result = AIOutputValidator.validate(week: try Fixture.week(), constraints: constraints(weeklyBudgetEur: 60))
        #expect(result.isValid)
        #expect(!result.warnings.contains { if case .weekOverBudgetWithinTolerance = $0 { true } else { false } })
    }

    @Test func allergenIsFatalAndReportedSeparately() {
        let peanuts = meal(name: "Salade thaï", ingredients: [ingredient("Arachides grillées", 20)])
        let result = AIOutputValidator.validate(meal: peanuts, constraints: constraints(allergies: ["arachide"]))
        #expect(result.fatal.contains(.allergen(meal: "Salade thaï", food: "arachide")))
    }

    @Test func dislikedFoodIsFatal() {
        let tuna = meal(name: "Pâtes au thon", ingredients: [ingredient("Pâtes", 80)])
        let result = AIOutputValidator.validate(meal: tuna, constraints: constraints(excludedFoods: ["thon"]))
        #expect(result.fatal.contains(.excludedFood(meal: "Pâtes au thon", food: "thon")))
    }

    @Test func dayAboveCostLimitIsFatal() throws {
        let day = try Fixture.week().days[0]
        let result = AIOutputValidator.validate(day: day, constraints: constraints(costLimitEur: 8), expectedOffset: 0)
        #expect(result.fatal.contains(.overCostLimit(costEur: 8.2, limitEur: 8)))
    }

    @Test func dayWithinCostLimitPasses() throws {
        let day = try Fixture.week().days[0]
        #expect(AIOutputValidator.validate(day: day, constraints: constraints(costLimitEur: 8.2), expectedOffset: 0).isValid)
    }

    @Test func mealAboveCostLimitIsFatal() {
        let result = AIOutputValidator.validate(meal: meal(cost: 3.5), constraints: constraints(costLimitEur: 3))
        #expect(result.fatal.contains(.overCostLimit(costEur: 3.5, limitEur: 3)))
    }

    @Test func dayLimitUsesCeilingMinusOtherDays() {
        // 56 × 1,10 − 6 × 8 = 13,60 €.
        #expect(abs(BudgetMath.dayLimit(weeklyBudget: 56, tolerance: 0.1, otherDaysCost: 48) - 13.6) < 0.0001)
        #expect(BudgetMath.dayLimit(weeklyBudget: 40, tolerance: 0, otherDaysCost: 50) == 0)
    }

    @Test func mealLimitUsesDayLimitMinusOtherMeals() {
        #expect(abs(BudgetMath.mealLimit(dayLimit: 9, otherMealsCost: 6.5) - 2.5) < 0.0001)
        #expect(BudgetMath.mealLimit(dayLimit: 5, otherMealsCost: 6) == 0)
    }
}
