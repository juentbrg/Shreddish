import Foundation
import Testing
@testable import ShreddishCore

struct PromptBuilderTests {
    static let preferences = PromptPreferences(
        mealsPerDay: 4, maxPrepMinutes: 20, weeklyBudgetEur: 56, budgetTolerance: 0.1,
        allergies: ["arachide"], dislikedFoods: ["thon"], likedFoods: ["poulet"], equipment: ["micro-ondes"],
        batchCooking: false, ingredientAvailability: .everywhere
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
        #expect(preferences["weekly_budget_eur"] as? Double == 56)
        #expect(preferences["budget_tolerance"] as? Double == 0.1)
        #expect(preferences["allergies"] as? [String] == ["arachide"])
        #expect(preferences["disliked_foods"] as? [String] == ["thon"])
        #expect(preferences["ingredient_availability"] as? String == "everywhere")
        #expect(preferences["store"] == nil)
        #expect((input["reference_prices_eur_per_kg"] as? String)?.contains("graines de chia") == true)
        #expect(input["cost_limit_eur"] == nil)
        #expect(preferences["batch_cooking"] as? Bool == false)
        #expect(input["day_offset"] == nil)
    }

    @Test func noPersonalDataIsSent() throws {
        let texts = [
            PromptBuilder.weekInput(targets: referenceTargets, goal: .cut, preferences: Self.preferences),
            PromptBuilder.dayInput(
                targets: referenceTargets, goal: .cut, preferences: Self.preferences, dayOffset: 2, avoidMealNames: ["A"],
                costLimitEur: 9
            ),
            PromptBuilder.replaceMealInput(
                targets: referenceTargets, goal: .cut, preferences: Self.preferences, dayOffset: 2,
                existingDayMeals: [meal(.breakfast)], mealTypeToReplace: .lunch, avoidMealNames: ["A"], costLimitEur: 3
            ),
        ]
        let allowed: Set<String> = [
            "task", "targets", "kcal", "protein_g", "carbs_g", "fat_g", "goal", "preferences",
            "meals_per_day", "max_prep_minutes", "weekly_budget_eur", "budget_tolerance", "allergies",
            "disliked_foods", "ingredient_availability", "cost_limit_eur", "liked_foods",
            "equipment", "batch_cooking", "day_offset", "existing_day_meals", "meal_type_to_replace",
            "remaining_targets", "avoid_meal_names", "type", "name", "owned_supplements", "training_time",
            "training_sessions_per_week", "previous_attempt_feedback", "reference_prices_eur_per_kg",
            "protein_g_per_serving", "serving_g", "kind", "kcal_per_serving", "carbs_g_per_serving",
            "fat_g_per_serving", "dose", "doses_per_day",
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
            avoidMealNames: ["Poulet riz"], costLimitEur: 9.5
        ))
        #expect(input["task"] as? String == "day")
        #expect(input["cost_limit_eur"] as? Double == 9.5)
        #expect(input["day_offset"] as? Int == 3)
        #expect(input["avoid_meal_names"] as? [String] == ["Poulet riz"])
    }

    @Test func replaceMealComputesRemainingTargets() throws {
        let breakfast = meal(.breakfast, kcal: 500, protein: 30, carbs: 60, fat: 15)
        let snack = meal(.snack, kcal: 350, protein: 30, carbs: 35, fat: 9)
        let input = try Self.json(PromptBuilder.replaceMealInput(
            targets: referenceTargets, goal: .cut, preferences: Self.preferences, dayOffset: 2,
            existingDayMeals: [breakfast, snack], mealTypeToReplace: .lunch, avoidMealNames: [], costLimitEur: 3
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
            existingDayMeals: [huge], mealTypeToReplace: .dinner, avoidMealNames: [], costLimitEur: 3
        ))
        let remaining = try #require(input["remaining_targets"] as? [String: Any])
        #expect(remaining["kcal"] as? Int == 0)
    }

    @Test func systemInstructionsStateHardRules() {
        let text = PromptBuilder.systemInstructions()
        #expect(text.contains("disliked_foods"))
        #expect(text.contains("max_prep_minutes"))
        #expect(text.contains("infeasible"))
        #expect(text.contains("allergies"))
        #expect(text.contains("weekly_budget_eur"))
        #expect(text.contains("cost_limit_eur"))
        #expect(text.contains("ingredient_availability"))
        #expect(text.contains("reference_prices_eur_per_kg"))
        #expect(text.contains("français"))
    }

    @Test func supplementDetailsReachThePromptByKind() throws {
        let preferences = Preferences()
        preferences.supplementList = ["Whey", "Créatine"]
        preferences.setSupplementInfo(
            SupplementInfo(servingG: 30, kcalPerServing: 118, proteinPerServingG: 24, carbsPerServingG: 2, fatPerServingG: 1.5),
            for: "whey"
        )
        preferences.setSupplementInfo(SupplementInfo(doseAmount: 5, doseUnit: .g, dosesPerDay: 1), for: "Créatine")
        let text = PromptBuilder.weekInput(targets: referenceTargets, goal: .cut, preferences: preferences.promptPreferences)
        #expect(text.contains(
            "{\"carbs_g_per_serving\":2,\"fat_g_per_serving\":1.5,\"kcal_per_serving\":118,\"kind\":\"macro\","
                + "\"name\":\"Whey\",\"protein_g_per_serving\":24,\"serving_g\":30}"
        ))
        #expect(text.contains("{\"dose\":\"5 g\",\"doses_per_day\":1,\"kind\":\"dose\",\"name\":\"Créatine\"}"))
        preferences.setSupplementInfo(SupplementInfo(), for: "Whey")
        preferences.setSupplementInfo(SupplementInfo(), for: "Créatine")
        #expect(preferences.supplementInfoData == nil)
    }

    @Test(arguments: [
        ("Whey", SupplementKind.macro), ("Isolat de whey", .macro), ("Caséine", .macro), ("Gainer", .macro),
        ("Barres protéinées", .macro), ("Créatine", .dose), ("Vitamine D", .dose), ("Oméga-3", .dose),
    ])
    func supplementKindIsInferred(name: String, kind: SupplementKind) {
        #expect(SupplementKind.infer(from: name) == kind)
    }
}
