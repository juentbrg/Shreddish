import Foundation
import Testing
@testable import ShreddishCore

struct AIOutputValidatorTests {
    @Test func validWeekPasses() throws {
        let result = AIOutputValidator.validate(week: try Fixture.week(), constraints: constraints())
        #expect(result.fatal.isEmpty)
        #expect(result.warnings.isEmpty)
        let week = try #require(result.sanitized)
        #expect(week.days.map(\.dayOffset) == Array(0...6))
    }

    @Test func sixDaysIsFatal() throws {
        var week = try Fixture.week()
        week.days.removeLast()
        let result = AIOutputValidator.validate(week: week, constraints: constraints())
        #expect(result.fatal.contains(.wrongDays))
        #expect(result.sanitized == nil)
    }

    @Test func duplicateOffsetIsFatal() throws {
        var week = try Fixture.week()
        week.days[6].dayOffset = 5
        #expect(AIOutputValidator.validate(week: week, constraints: constraints()).fatal.contains(.wrongDays))
    }

    @Test func daysAreSortedByOffset() throws {
        var week = try Fixture.week()
        week.days.reverse()
        let result = AIOutputValidator.validate(week: week, constraints: constraints())
        #expect(result.sanitized?.days.map(\.dayOffset) == Array(0...6))
    }

    @Test func mealCountMustMatchPreferences() throws {
        let result = AIOutputValidator.validate(week: try Fixture.week(), constraints: constraints(mealsPerDay: 3))
        #expect(result.fatal.contains(.wrongMealCount(dayOffset: 0, count: 4)))
    }

    @Test func incoherentKcalIsRecomputedFromMacros() {
        // 4 × 40 + 4 × 50 + 9 × 15,5 = 499,5 ; annoncé 800 → recalculé.
        let result = AIOutputValidator.validate(
            meal: meal(name: "Pâtes", kcal: 800), constraints: constraints()
        )
        #expect(result.fatal.isEmpty)
        #expect(result.corrected.contains(.kcalRecomputed(meal: "Pâtes")))
        #expect(result.sanitized?.kcal == 499.5)
    }

    @Test func kcalWithinTenPercentIsKept() {
        let result = AIOutputValidator.validate(meal: meal(kcal: 540), constraints: constraints())
        #expect(result.corrected.isEmpty)
        #expect(result.sanitized?.kcal == 540)
    }

    @Test func prepTooLongIsFatal() {
        let result = AIOutputValidator.validate(meal: meal(name: "Lasagnes", prep: 45), constraints: constraints())
        #expect(result.fatal.contains(.prepTooLong(meal: "Lasagnes", minutes: 45)))
    }

    @Test func excludedFoodIsFatalIgnoringCaseAndAccents() {
        let tuna = meal(name: "Salade composée", ingredients: [ingredient("Thon au naturel", 100)])
        let result = AIOutputValidator.validate(meal: tuna, constraints: constraints(excludedFoods: ["THÔN"]))
        #expect(result.fatal.contains(.excludedFood(meal: "Salade composée", food: "THÔN")))
    }

    @Test func excludedFoodMatchesPlural() {
        let eggs = meal(name: "Omelette", ingredients: [ingredient("Œufs", 3, "piece")])
        let result = AIOutputValidator.validate(meal: eggs, constraints: constraints(excludedFoods: ["oeuf"]))
        #expect(!result.fatal.isEmpty)
    }

    @Test func dayOffTargetIsWarning() throws {
        var week = try Fixture.week()
        week.days[2].meals[3] = meal(.dinner, name: "Gros dîner", kcal: 1499.5, protein: 100, carbs: 200, fat: 33.5)
        let result = AIOutputValidator.validate(week: week, constraints: constraints())
        #expect(result.fatal.isEmpty)
        #expect(result.warnings.contains { if case .dayOffTarget(dayOffset: 2, _) = $0 { true } else { false } })
    }

    @Test func dayOverBudgetIsWarning() throws {
        // Coût fixture : 8,20 € / jour. Budget 7 € → 110 % = 7,70 € → signalé.
        let result = AIOutputValidator.validate(week: try Fixture.week(), constraints: constraints(dailyBudgetEur: 7))
        #expect(result.fatal.isEmpty)
        #expect(result.warnings.contains { if case .dayOverBudget(dayOffset: 0, _) = $0 { true } else { false } })
    }

    @Test func dayWithinTenPercentOfBudgetIsNotFlagged() throws {
        // 8,20 € ≤ 7,5 × 1,1 = 8,25 €.
        let result = AIOutputValidator.validate(week: try Fixture.week(), constraints: constraints(dailyBudgetEur: 7.5))
        #expect(!result.warnings.contains { if case .dayOverBudget = $0 { true } else { false } })
    }

    @Test func batchCookingRequiresOneOrTwoSessions() throws {
        let result = AIOutputValidator.validate(week: try Fixture.week(), constraints: constraints(batchCooking: true))
        #expect(result.fatal.contains(.prepSessionCount(0)))
    }

    @Test func batchCookingOrphanReferenceIsFatal() throws {
        var week = try Fixture.week()
        week.prepSessions = [PrepSessionDTO(index: 0, dayOffset: 0, title: "Prep", durationMinutes: 60, steps: ["Cuire"])]
        week.days[1].meals[1].prepSessionRef = 3
        let result = AIOutputValidator.validate(week: week, constraints: constraints(batchCooking: true))
        #expect(result.fatal.contains(.orphanPrepSessionRef(meal: week.days[1].meals[1].name, ref: 3)))
    }

    @Test func batchCookingValidReferencePasses() throws {
        var week = try Fixture.week()
        week.prepSessions = [PrepSessionDTO(index: 0, dayOffset: 0, title: "Prep", durationMinutes: 60, steps: ["Cuire"])]
        week.days[1].meals[1].prepSessionRef = 0
        let result = AIOutputValidator.validate(week: week, constraints: constraints(batchCooking: true))
        #expect(result.fatal.isEmpty)
    }

    @Test func batchOffClearsReferencesAndSessions() throws {
        var week = try Fixture.week()
        week.prepSessions = [PrepSessionDTO(index: 0, dayOffset: 0, title: "Prep", durationMinutes: 60, steps: ["Cuire"])]
        week.days[1].meals[1].prepSessionRef = 0
        let result = AIOutputValidator.validate(week: week, constraints: constraints(batchCooking: false))
        #expect(result.fatal.isEmpty)
        #expect(result.sanitized?.prepSessions.isEmpty == true)
        #expect(result.sanitized?.days[1].meals[1].prepSessionRef == nil)
        #expect(result.corrected.contains(.prepSessionRefCleared(meal: week.days[1].meals[1].name)))
    }

    @Test func unitsAreNormalized() {
        let source = meal(ingredients: [
            ingredient("Riz", 1, "kg"), ingredient("Lait", 0.5, "l"), ingredient("Crème", 20, "cl"),
            ingredient("Œuf", 2, "pièce"),
        ])
        let result = AIOutputValidator.validate(meal: source, constraints: constraints())
        let ingredients = result.sanitized?.ingredients ?? []
        #expect(ingredients.map(\.unit) == ["g", "ml", "ml", "piece"])
        #expect(ingredients.map(\.quantity) == [1000, 500, 200, 2])
    }

    @Test func unknownUnitIsFatal() {
        let result = AIOutputValidator.validate(
            meal: meal(ingredients: [ingredient("Sel", 1, "pincée")]), constraints: constraints()
        )
        #expect(result.fatal.contains(.invalidUnit(ingredient: "Sel", unit: "pincée")))
    }

    @Test func emptyMealIsFatal() {
        var source = meal(name: "Vide")
        source.ingredients = []
        #expect(!AIOutputValidator.validate(meal: source, constraints: constraints()).fatal.isEmpty)
    }

    @Test func replacementMealKeepsRequestedType() {
        let result = AIOutputValidator.validate(
            meal: meal(.dinner), constraints: constraints(), expectedType: .lunch
        )
        #expect(result.sanitized?.type == .lunch)
    }

    @Test func dayValidationForcesOffset() throws {
        var day = try Fixture.week().days[0]
        day.dayOffset = 5
        let result = AIOutputValidator.validate(day: day, constraints: constraints(), expectedOffset: 2)
        #expect(result.sanitized?.dayOffset == 2)
    }
}
