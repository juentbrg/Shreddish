import Foundation
import SwiftData
import Testing
@testable import ShreddishCore

@MainActor
struct SavedRecipeTests {
    static func day(_ meals: [MealDTO]) -> DayPlanDTO { DayPlanDTO(dayOffset: 0, meals: meals) }

    static func unwritten(_ meal: MealDTO) -> MealDTO {
        var meal = meal
        meal.steps = []
        return meal
    }

    @Test func toggleSavesThenRemovesByName() throws {
        let container = try ShreddishStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let curry = meal(.dinner, name: "Curry de pois chiches")
        #expect(RecipeBook.toggle(curry, at: .now, in: context))
        let saved = try #require(RecipeBook.saved(named: "curry de pois chiche", in: context))
        #expect(saved.dto.ingredients == curry.ingredients)
        #expect(saved.steps == ["Cuire."])
        #expect(saved.type == .dinner)
        #expect(!RecipeBook.toggle(curry, at: .now, in: context))
        #expect(try context.fetch(FetchDescriptor<SavedRecipe>()).isEmpty)
    }

    @Test func stepsComeBackWhenRecipeIsKeptAsIs() {
        let recipe = meal(.dinner, name: "Curry", ingredients: [ingredient("Pois chiches", 200), ingredient("Riz", 80)])
        let placed = Self.unwritten(meal(.dinner, name: "curry", ingredients: [ingredient("Riz", 85), ingredient("Pois chiches", 200)]))
        let other = Self.unwritten(meal(.lunch, name: "Salade"))
        let days = SavedRecipeMatcher.restoreSteps([Self.day([placed, other])], recipes: [recipe])
        #expect(days[0].meals[0].steps == ["Cuire."])
        #expect(days[0].meals[1].steps.isEmpty)
    }

    @Test func stepsAreRewrittenWhenQuantitiesChange() {
        let recipe = meal(.dinner, name: "Curry", ingredients: [ingredient("Pois chiches", 200), ingredient("Riz", 80)])
        let scaled = Self.unwritten(meal(.dinner, name: "Curry", ingredients: [ingredient("Pois chiches", 260), ingredient("Riz", 80)]))
        let changed = Self.unwritten(meal(.dinner, name: "Curry", ingredients: [ingredient("Pois chiches", 200)]))
        let days = SavedRecipeMatcher.restoreSteps([Self.day([scaled]), Self.day([changed])], recipes: [recipe])
        #expect(days.allSatisfy { $0.meals[0].steps.isEmpty })
    }

    @Test func recipesAreSpreadOverDaysWhenRequestedDayByDay() {
        let recipes = (0..<9).map { meal(name: "R\($0)") }
        #expect(SavedRecipeMatcher.recipes(recipes, forDay: 0).map(\.name) == ["R0", "R7"])
        #expect(SavedRecipeMatcher.recipes(recipes, forDay: 3).map(\.name) == ["R3"])
        // Période de 3 jours : les 9 recettes réparties sur les 3 jours, aucune perdue.
        let short = (0..<3).flatMap { SavedRecipeMatcher.recipes(recipes, forDay: $0, dayCount: 3) }
        #expect(short.count == 9)
    }
}
