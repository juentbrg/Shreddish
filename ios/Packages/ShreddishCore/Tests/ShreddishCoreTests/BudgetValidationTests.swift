import Testing
@testable import ShreddishCore

struct BudgetValidationTests {
    // Coût fixture : 8,20 € / jour, 57,40 € / semaine.

    @Test func weekAboveCeilingIsAcceptedWithWarning() throws {
        // Spec 004 : plus bloquant, le générateur refait un essai puis accepte.
        let result = AIOutputValidator.validate(
            week: try Fixture.week(), constraints: constraints(weeklyBudgetEur: 56, budgetTolerance: 0)
        )
        #expect(result.isValid)
        #expect(result.sanitized != nil)
        #expect(result.warnings.contains(.weekOverBudget(costEur: 57.4, ceilingEur: 56)))
        #expect(result.overCeiling?.costEur == 57.4)
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

    @Test func dayAboveCostLimitIsWarning() throws {
        let day = try Fixture.week().days[0]
        let result = AIOutputValidator.validate(day: day, constraints: constraints(costLimitEur: 8), expectedOffset: 0)
        #expect(result.isValid)
        #expect(result.warnings.contains(.overCostLimit(costEur: 8.2, limitEur: 8)))
    }

    @Test func dayWithinCostLimitPasses() throws {
        let day = try Fixture.week().days[0]
        #expect(AIOutputValidator.validate(day: day, constraints: constraints(costLimitEur: 8.2), expectedOffset: 0).isValid)
    }

    @Test func ownedSupplementCostsNothing() throws {
        let shake = meal(
            .snack, name: "Shake whey banane", cost: 1.4,
            ingredients: [ingredient("Whey protéine", 30, cost: 1.1), ingredient("Banane", 1, "piece", cost: 0.3)]
        )
        let result = AIOutputValidator.validate(meal: shake, constraints: constraints(ownedSupplements: ["Whey"]))
        let sanitized = try #require(result.sanitized)
        #expect(abs(sanitized.costEur - 0.3) < 0.0001)
        #expect(sanitized.ingredients[0].costEur == 0)
        #expect(result.corrected.contains(.supplementCostCleared(meal: "Shake whey banane")))
    }

    @Test(arguments: [("12:30", true), ("7:05", true), ("23:59", true), ("24:00", false), ("midi", false), ("12h30", false)])
    func mealTime(time: String, valid: Bool) throws {
        let result = AIOutputValidator.validate(meal: meal(time: time), constraints: constraints())
        let sanitized = try #require(result.sanitized)
        #expect((sanitized.time != nil) == valid)
    }

    @Test func overBudgetFeedbackNamesCostAndCeiling() {
        let text = PromptBuilder.overBudgetFeedback(costEur: 95.123, ceilingEur: 92)
        #expect(text.contains("95.12"))
        #expect(text.contains("92"))
        #expect(text.contains("yaourt nature 0 %"))
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
