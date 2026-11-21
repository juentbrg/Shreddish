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
}
