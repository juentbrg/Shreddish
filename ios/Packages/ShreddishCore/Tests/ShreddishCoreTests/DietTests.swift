import Foundation
import Testing
@testable import ShreddishCore

/// Régimes (spec 017, FR-1703).
struct DietTests {
    func violation(_ names: [String], _ diets: [Diet], dish: String = "Plat") -> String? {
        Diet.violation(in: meal(name: dish, ingredients: names.map { ingredient($0, 100) }), diets: diets)?.food
    }

    @Test func vegetarianRejectsMeatAndFish() {
        #expect(violation(["Blanc de poulet", "Riz"], [.vegetarian]) == "Blanc de poulet")
        #expect(violation(["Thon au naturel"], [.vegetarian]) == "Thon au naturel")
        #expect(violation(["Lentilles vertes", "Oignon haché"], [.vegetarian]) == nil)
        #expect(violation(["Steak végétal"], [.vegetarian]) == nil)
    }

    @Test func pescatarianAllowsFish() {
        #expect(violation(["Saumon"], [.pescatarian]) == nil)
        #expect(violation(["Jambon blanc"], [.pescatarian]) == "Jambon blanc")
    }

    @Test func veganRejectsAnimalProductsButNotPlantMilks() {
        #expect(violation(["Œufs"], [.vegan]) == "Œufs")
        #expect(violation(["Fromage blanc 0 %"], [.vegan]) == "Fromage blanc 0 %")
        #expect(violation(["Lait de coco", "Beurre de cacahuète", "Tofu"], [.vegan]) == nil)
        #expect(violation(["Lait de coco"], [.vegan], dish: "Poulet au lait de coco") == "Poulet au lait de coco")
    }

    @Test func halalAndKosher() {
        #expect(violation(["Lardons"], [.halal]) == "Lardons")
        #expect(violation(["Poulet"], [.halal]) == nil)
        #expect(violation(["Crevettes"], [.kosher]) == "Crevettes")
    }

    @Test func glutenAndLactoseFree() {
        #expect(violation(["Pâtes complètes"], [.glutenFree]) == "Pâtes complètes")
        #expect(violation(["Pain sans gluten", "Patate douce", "Riz"], [.glutenFree]) == nil)
        #expect(violation(["Yaourt nature"], [.lactoseFree]) == "Yaourt nature")
        #expect(violation(["Lait sans lactose", "Laitue"], [.lactoseFree]) == nil)
    }

    @Test func validatorRejectsDietViolations() {
        var constraints = constraints()
        constraints.diets = [.vegetarian]
        let result = AIOutputValidator.validate(meal: meal(name: "Poulet riz", ingredients: [ingredient("Poulet", 120)]),
                                                constraints: constraints)
        #expect(result.fatal.contains(.dietViolation(meal: "Poulet riz", food: "Poulet riz", diet: "vegetarian")))
    }
}
