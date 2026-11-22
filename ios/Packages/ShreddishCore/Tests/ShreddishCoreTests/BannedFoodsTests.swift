import Foundation
import SwiftData
import Testing
@testable import ShreddishCore

/// Aliments bannis depuis une recette ou la liste de courses.
@MainActor
struct BannedFoodsTests {
    @Test func banAddsOnceIgnoringCaseAndPlural() throws {
        let container = try ShreddishStore.makeContainer(inMemory: true)
        let prefs = Preferences()
        container.mainContext.insert(prefs)
        #expect(prefs.ban(" Baguette "))
        #expect(!prefs.ban("baguettes"))
        #expect(!prefs.ban(""))
        #expect(prefs.excludedFoods == ["Baguette"])
        #expect(prefs.isBanned("BAGUETTE"))
        #expect(!prefs.isBanned("Pain complet"))
    }

    @Test func bannedFoodIsRejectedByValidator() {
        let meal = MealDTO(
            type: .lunch, name: "Poulet et poêlée", ingredients: [ingredient("Poêlée de légumes surgelés", 200)],
            steps: ["Cuire"], prepMinutes: 10, costEur: 2, kcal: 400, proteinG: 30, carbsG: 30, fatG: 10, prepSessionRef: nil
        )
        #expect(AIOutputValidator.excludedFood(in: meal, excluded: ["poêlée de légumes surgelés"]) != nil)
        #expect(AIOutputValidator.excludedFood(in: meal, excluded: ["baguette"]) == nil)
    }

    @Test func upcomingMealsWithAnyBannedFoodSkipPastAndEatenMeals() throws {
        let (container, context, targets) = try PlanStoreTests.setup()
        _ = container
        let plan = try PlanStore.saveWeek(
            try Fixture.week(), startDay: PlanStoreTests.start, targets: targets, createdAt: .now, in: context
        )
        let today = PlanStoreTests.start.adding(days: 2)
        let food = try #require(plan.sortedDays[3].sortedMeals.first?.ingredients.first?.name)
        let meals = PlanStore.upcomingMeals(containingAnyOf: ["introuvable", food], from: today, in: context)
        #expect(!meals.isEmpty)
        #expect(meals.allSatisfy { ($0.day?.day ?? today) >= today && $0.status == .planned })
        meals[0].status = .eaten
        #expect(PlanStore.upcomingMeals(containingAnyOf: [food], from: today, in: context).count == meals.count - 1)
        #expect(PlanStore.upcomingMeals(containingAnyOf: [], from: today, in: context).isEmpty)
    }

    @Test func shoppingLabelFindsIngredientNamedDifferently() {
        // Ingrédient rattaché au produit « Steak haché 5 % » sans le contenir dans son nom.
        let meal = MealDTO(
            type: .dinner, name: "Bœuf et riz", ingredients: [ingredient("boeuf hache 5", 150, aisle: .viandePoisson)],
            steps: ["Cuire"], prepMinutes: 10, costEur: 3, kcal: 400, proteinG: 30, carbsG: 30, fatG: 10, prepSessionRef: nil
        )
        #expect(PriceCatalog.shared.purchase(for: meal.ingredients[0])?.product.label == "Steak haché 5 %")
        #expect(AIOutputValidator.excludedFood(in: meal, excluded: ["Steak haché 5 %"]) != nil)
    }
}
