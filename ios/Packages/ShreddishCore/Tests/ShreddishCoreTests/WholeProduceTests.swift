import Foundation
import SwiftData
import Testing
@testable import ShreddishCore

struct WholeProduceTests {
    static func item(_ name: String, _ quantity: Double, _ unit: String = "g", code: Int? = nil, pieceG: Double? = nil) -> IngredientDTO {
        IngredientDTO(
            name: name, quantity: quantity, unit: unit, aisle: .fruitsLegumes, costEur: 0, unitPriceEur: 8,
            pieceG: pieceG, foodCode: code
        )
    }

    static func meal(_ ingredients: [IngredientDTO], steps: [String] = []) -> MealDTO {
        MealDTO(
            type: .lunch, name: "Bol", ingredients: ingredients, steps: steps, prepMinutes: 10, costEur: 0,
            kcal: 500, proteinG: 30, carbsG: 50, fatG: 15, prepSessionRef: nil
        )
    }

    @Test func avocadoGramsBecomeHalfAvocado() {
        // Avocat de 200 g, 70 % mangeable : ½ avocat = 70 g.
        let avocado = WholeProduce.snapped(Self.item("Avocat", 30, code: 13004))
        #expect(avocado.quantity == 70)
        #expect(WholeProduce.pieces(of: avocado) == 0.5)
        #expect(avocado.costEur == 0.56)
        #expect(WholeProduce.snapped(Self.item("Avocat", 120, code: 13004)).quantity == 140)
        #expect(WholeProduce.snapped(Self.item("Avocat", 0.3, "piece", code: 13004, pieceG: 200)).quantity == 0.5)
    }

    @Test func kiwiIsWholeAndPotatoUntouched() {
        #expect(WholeProduce.pieces(of: Self.item("Kiwi", 20, code: 13021)) == 1)
        #expect(WholeProduce.snapped(Self.item("Pomme de terre", 30, code: 4002)).quantity == 30)
        #expect(WholeProduce.snapped(Self.item("Tomate", 30)).quantity == 30)
        // Formes transformées : quantité libre (oignon séché, zeste de citron).
        #expect(WholeProduce.snapped(Self.item("Oignon séché", 5, code: 20180)).quantity == 5)
        #expect(WholeProduce.snapped(Self.item("Zeste de citron", 2, code: 13125)).quantity == 2)
        // Sans code Ciqual : produit retrouvé par son nom.
        #expect(WholeProduce.snapped(Self.item("Banane", 30)).quantity == 59)
    }

    @Test func adjusterKeepsHalfAvocado() {
        let resolver = NutritionResolver(cache: InMemoryFoodMatchCache(), supplements: [])
        let meal = resolver.resolve(WholeProduce.snap(Self.meal([
            Self.item("Filet de poulet cru", 150, code: 36017), Self.item("Riz basmati cru", 80),
            Self.item("Avocat", 30, code: 13004),
        ]))).meal
        let targets = MacroTotals(kcal: 1200, proteinG: 90, carbsG: 120, fatG: 40)
        let adjusted = PortionAdjuster.adjust([meal], to: targets, resolver: resolver, oil: nil)[0]
        #expect(adjusted.ingredients.first { $0.name == "Avocat" }?.quantity == 70)
        #expect(adjusted.ingredients.first { $0.name == "Filet de poulet cru" }?.quantity != 150)
    }

    @Test func stepsWithOtherQuantitiesAreStale() {
        let ingredients = [Self.item("Riz basmati cru", 75), Self.item("Whey", 52.5), Self.item("Ail", 1)]
        #expect(RecipeConsistency.stepsMatch(Self.meal(ingredients, steps: ["Rince 75 g de riz.", "Ajoute 52,5 g de whey."])))
        #expect(!RecipeConsistency.stepsMatch(Self.meal(ingredients, steps: ["Rince 70 g de riz.", "Ajoute 52,5 g de whey."])))
        #expect(RecipeConsistency.stepsMatch(Self.meal(ingredients)))
        let avocado = [Self.item("Avocat", 70, code: 13004)]
        #expect(RecipeConsistency.stepsMatch(Self.meal(avocado, steps: ["Tranche ½ avocat."])))
    }

    @MainActor
    @Test func staleRecipesAreClearedFromToday() throws {
        let container = try ShreddishStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let targets = try NutritionCalculator.targets(for: NutritionCalculatorTests.man)
        let start = LocalDay(year: 2026, month: 11, day: 22)
        let plan = try PlanStore.saveWeek(try Fixture.week(), startDay: start, targets: targets, createdAt: .now, in: context)
        for meal in plan.days.flatMap(\.meals) { meal.steps = ["Mélange 1 g de tout."] }
        let yesterday = try #require(plan.sortedDays.first?.meals.first)

        let cleared = PlanStore.clearStaleRecipes(from: start.adding(days: 1), in: context)

        #expect(cleared == plan.sortedDays.dropFirst().flatMap(\.meals).count)
        #expect(!yesterday.steps.isEmpty)
        #expect(plan.sortedDays[1].meals.allSatisfy { $0.needsRecipe })
    }
}
