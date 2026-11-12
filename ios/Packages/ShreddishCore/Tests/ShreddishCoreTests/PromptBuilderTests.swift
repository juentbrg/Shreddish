import Foundation
import Testing
@testable import ShreddishCore

struct PromptBuilderTests {
    static let preferences = PromptPreferences(
        mealsPerDay: 4, maxPrepMinutes: 20, dailyBudgetEur: 8, excludedFoods: ["thon"],
        likedFoods: ["poulet"], equipment: ["micro-ondes"], batchCooking: false
    )

    static func json(_ text: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try #require(object as? [String: Any])
    }

    /// Toutes les clés d'un JSON, récursivement.
    static func allKeys(_ value: Any) -> Set<String> {
        if let dict = value as? [String: Any] {
            return dict.reduce(into: Set(dict.keys)) { $0.formUnion(allKeys($1.value)) }
        }
        if let array = value as? [Any] {
            return array.reduce(into: Set<String>()) { $0.formUnion(allKeys($1)) }
        }
        return []
    }

    @Test func weekInputMatchesContract() throws {
        let input = try Self.json(PromptBuilder.weekInput(targets: referenceTargets, goal: .cut, preferences: Self.preferences))
        #expect(input["task"] as? String == "week")
        #expect(input["goal"] as? String == "cut")
        let targets = try #require(input["targets"] as? [String: Any])
        #expect(targets["kcal"] as? Int == 2207)
        #expect(targets["protein_g"] as? Int == 160)
        let preferences = try #require(input["preferences"] as? [String: Any])
        #expect(preferences["meals_per_day"] as? Int == 4)
        #expect(preferences["daily_budget_eur"] as? Double == 8)
        #expect(preferences["excluded_foods"] as? [String] == ["thon"])
        #expect(preferences["batch_cooking"] as? Bool == false)
        #expect(input["day_offset"] == nil)
    }

    @Test func noPersonalDataIsSent() throws {
        let texts = [
            PromptBuilder.weekInput(targets: referenceTargets, goal: .cut, preferences: Self.preferences),
            PromptBuilder.dayInput(
                targets: referenceTargets, goal: .cut, preferences: Self.preferences, dayOffset: 2, avoidMealNames: ["A"]
            ),
            PromptBuilder.replaceMealInput(
                targets: referenceTargets, goal: .cut, preferences: Self.preferences, dayOffset: 2,
                existingDayMeals: [meal(.breakfast)], mealTypeToReplace: .lunch, avoidMealNames: ["A"]
            ),
        ]
        let allowed: Set<String> = [
            "task", "targets", "kcal", "protein_g", "carbs_g", "fat_g", "goal", "preferences",
            "meals_per_day", "max_prep_minutes", "daily_budget_eur", "excluded_foods", "liked_foods",
            "equipment", "batch_cooking", "day_offset", "existing_day_meals", "meal_type_to_replace",
            "remaining_targets", "avoid_meal_names", "type", "name",
        ]
        for text in texts {
            let keys = Self.allKeys(try JSONSerialization.jsonObject(with: Data(text.utf8)))
            #expect(keys.isSubset(of: allowed), "Clés non autorisées : \(keys.subtracting(allowed))")
            for forbidden in ["age", "weight", "weight_kg", "sex", "height", "height_cm", "bmr", "tdee"] {
                #expect(!keys.contains(forbidden))
            }
        }
    }

    @Test func dayInputCarriesOffsetAndAvoidList() throws {
        let input = try Self.json(PromptBuilder.dayInput(
            targets: referenceTargets, goal: .cut, preferences: Self.preferences, dayOffset: 3,
            avoidMealNames: ["Poulet riz"]
        ))
        #expect(input["task"] as? String == "day")
        #expect(input["day_offset"] as? Int == 3)
        #expect(input["avoid_meal_names"] as? [String] == ["Poulet riz"])
    }

    @Test func replaceMealComputesRemainingTargets() throws {
        let breakfast = meal(.breakfast, kcal: 500, protein: 30, carbs: 60, fat: 15)
        let snack = meal(.snack, kcal: 350, protein: 30, carbs: 35, fat: 9)
        let input = try Self.json(PromptBuilder.replaceMealInput(
            targets: referenceTargets, goal: .cut, preferences: Self.preferences, dayOffset: 2,
            existingDayMeals: [breakfast, snack], mealTypeToReplace: .lunch, avoidMealNames: []
        ))
        #expect(input["task"] as? String == "replace_meal")
        #expect(input["meal_type_to_replace"] as? String == "lunch")
        let remaining = try #require(input["remaining_targets"] as? [String: Any])
        #expect(remaining["kcal"] as? Int == 1357)     // 2207 − 850
        #expect(remaining["protein_g"] as? Int == 100) // 160 − 60
        #expect(remaining["fat_g"] as? Int == 40)      // 64 − 24
        let existing = try #require(input["existing_day_meals"] as? [[String: Any]])
        #expect(existing.count == 2)
    }

    @Test func remainingTargetsNeverNegative() throws {
        let huge = meal(.breakfast, kcal: 3000, protein: 300, carbs: 300, fat: 100)
        let input = try Self.json(PromptBuilder.replaceMealInput(
            targets: referenceTargets, goal: .cut, preferences: Self.preferences, dayOffset: 0,
            existingDayMeals: [huge], mealTypeToReplace: .dinner, avoidMealNames: []
        ))
        let remaining = try #require(input["remaining_targets"] as? [String: Any])
        #expect(remaining["kcal"] as? Int == 0)
    }

    @Test func systemInstructionsStateHardRules() {
        let text = PromptBuilder.systemInstructions()
        #expect(text.contains("excluded_foods"))
        #expect(text.contains("max_prep_minutes"))
        #expect(text.contains("infeasible"))
        #expect(text.contains("français"))
    }
}
