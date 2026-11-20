import Foundation
import SwiftData
import Testing
@testable import ShreddishCore

/// Journal rapide et repas mangé en partie (spec 017, FR-1716).
@MainActor
struct QuickLogTests {
    let container: ModelContainer
    let day: DayPlan

    init() throws {
        container = try ShreddishStore.makeContainer(inMemory: true)
        let targets = try NutritionCalculator.targets(for: NutritionCalculatorTests.man)
        let plan = try PlanStore.saveWeek(
            WeekPlanDTO(prepSessions: [], days: [DayPlanDTO(dayOffset: 0, meals: [meal(kcal: 600)])]),
            startDay: LocalDay(year: 2026, month: 11, day: 20), targets: targets, createdAt: .now, in: container.mainContext
        )
        day = try #require(plan.days.first)
    }

    var context: ModelContext { container.mainContext }

    @Test func loggingAddsAnExtraAndARecent() throws {
        let per100 = MacroTotals(kcal: 540, proteinG: 7, carbsG: 57, fatG: 31)
        QuickLog.log(name: "Chocolat au lait", per100g: per100, grams: 20, barcode: "3017620422003", to: day, at: .now, in: context)
        let extra = try #require(day.extras.first)
        #expect(extra.kcal == 108)
        #expect(extra.quantityLabel == "20 g")
        QuickLog.log(name: "Chocolat au lait", per100g: per100, grams: 30, barcode: "3017620422003", to: day, at: .now, in: context)
        let foods = try context.fetch(FetchDescriptor<QuickFood>())
        #expect(foods.count == 1)
        #expect(foods.first?.useCount == 2)
        #expect(foods.first?.lastGrams == 30)
    }

    @Test func favoritesComeFirst() {
        let old = QuickFood(name: "Pomme", per100g: .zero, grams: 150, usedAt: .distantPast)
        old.isFavorite = true
        context.insert(old)
        context.insert(QuickFood(name: "Banane", per100g: .zero, grams: 120, usedAt: .now))
        #expect(QuickLog.suggestions(in: context).map(\.name) == ["Pomme", "Banane"])
    }

    @Test func partlyEatenMealCountsItsFraction() throws {
        let meal = try #require(day.meals.first)
        meal.setStatus(.eaten, at: .now)
        #expect(day.actualTotals.kcal == 600)
        meal.eatenFraction = 0.5
        #expect(day.actualTotals.kcal == 300)
    }
}
