import Foundation
import Testing
@testable import ShreddishCore

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func week() throws -> WeekPlanDTO {
        try AIResponseDecoder.decodeWeek(data("valid_week"))
    }
}

/// Cible de référence (homme 30 ans, sèche) : contracts/core-api.md.
let referenceTargets = MacroTotals(kcal: 2207, proteinG: 160, carbsG: 248, fatG: 64)

func constraints(
    mealsPerDay: Int = 4, maxPrepMinutes: Int = 20, weeklyBudgetEur: Double = 70, budgetTolerance: Double = 0.1,
    batchCooking: Bool = false, allergies: [String] = [], excludedFoods: [String] = [], costLimitEur: Double? = nil,
    ownedSupplements: [String] = []
) -> GenerationConstraints {
    GenerationConstraints(
        targets: referenceTargets, mealsPerDay: mealsPerDay, maxPrepMinutes: maxPrepMinutes,
        weeklyBudgetEur: weeklyBudgetEur, budgetTolerance: budgetTolerance, batchCooking: batchCooking,
        allergies: allergies, excludedFoods: excludedFoods, costLimitEur: costLimitEur,
        ownedSupplements: ownedSupplements
    )
}

func ingredient(
    _ name: String, _ quantity: Double, _ unit: String = "g", aisle: Aisle = .epicerie, cost: Double = 0.5
) -> IngredientDTO {
    IngredientDTO(name: name, quantity: quantity, unit: unit, aisle: aisle, costEur: cost)
}

func meal(
    _ type: MealType = .lunch, name: String = "Repas", kcal: Double = 500,
    protein: Double = 40, carbs: Double = 50, fat: Double = 15.5,
    prep: Int = 15, cost: Double = 2, ingredients: [IngredientDTO]? = nil, prepSessionRef: Int? = nil,
    time: String? = nil
) -> MealDTO {
    MealDTO(
        type: type, name: name, ingredients: ingredients ?? [ingredient("Riz", 80)],
        steps: ["Cuire."], prepMinutes: prep, costEur: cost,
        kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat, prepSessionRef: prepSessionRef,
        time: time
    )
}
