import Foundation
import SwiftData
import Testing
@testable import ShreddishCore

/// Repas modifié par l'utilisateur et recherche Ciqual (spec 017, FR-1705).
@MainActor
struct MealEditTests {
    @Test func searchFindsCiqualFoods() {
        let results = FoodSearch.search("riz basmati")
        #expect(!results.isEmpty)
        #expect(results.first?.name.localizedCaseInsensitiveContains("riz") == true)
        #expect(FoodSearch.search("r").isEmpty)
    }

    @Test func chosenFoodCodeIsKept() throws {
        let food = try #require(FoodSearch.search("lentille verte").first)
        var ingredient = ingredient("Mes lentilles", 100)
        ingredient.foodCode = food.code
        let resolver = NutritionResolver(cache: InMemoryFoodMatchCache())
        let resolved = resolver.resolve(meal(ingredients: [ingredient]), keepCodes: true)
        #expect(resolved.verified)
        #expect(resolved.meal.ingredients.first?.foodCode == food.code)
        #expect(abs(resolved.meal.kcal - food.per100g.kcal) < 1)
    }

    @Test func updatedMealKeepsStatusAndRebuildsShopping() throws {
        let container = try ShreddishStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let targets = try NutritionCalculator.targets(for: NutritionCalculatorTests.man)
        let plan = try PlanStore.saveWeek(
            WeekPlanDTO(prepSessions: [], days: [DayPlanDTO(dayOffset: 0, meals: [meal(name: "Poulet riz", time: "12:30")])]),
            startDay: LocalDay(year: 2026, month: 11, day: 20), targets: targets, createdAt: .now, in: context
        )
        let stored = try #require(plan.days.first?.meals.first)
        stored.setStatus(.eaten, at: .now)
        var edited = stored.dto
        edited.name = "Poulet patate douce"
        edited.ingredients = [ingredient("Patate douce", 250)]
        try PlanStore.updateMeal(stored, with: edited, in: context)
        #expect(stored.name == "Poulet patate douce")
        #expect(stored.status == .eaten)
        #expect(stored.time == "12:30")
        #expect(plan.shoppingItems.map(\.name).contains { $0.localizedCaseInsensitiveContains("patate") })
    }
}
