import Foundation
import SwiftData

/// Préférences de génération (FR-007, FR-008), singleton.
@Model
public final class Preferences {
    public static let mealsPerDayRange = 2...5
    public static let maxPrepMinutesRange = 5...90
    public static let dailyBudgetRange = 3.0...40.0
    /// Modèle OpenAI par défaut (research R4), modifiable dans Profil → Préférences.
    public static let defaultAIModel = "gpt-5-mini"

    /// 2–5, collations incluses. Défaut 4 (3 repas + 1 collation).
    public var mealsPerDay: Int
    /// 5–90 min. Défaut 20.
    public var maxPrepMinutes: Int
    /// 3–40 €. Défaut 8.
    public var dailyBudgetEUR: Double
    public var excludedFoods: [String]
    public var likedFoods: [String]
    public var equipment: [String]
    /// FR-014, désactivé par défaut.
    public var batchCooking: Bool
    public var aiModel: String

    public init() {
        mealsPerDay = 4
        maxPrepMinutes = 20
        dailyBudgetEUR = 8
        excludedFoods = []
        likedFoods = []
        equipment = []
        batchCooking = false
        aiModel = Self.defaultAIModel
    }

    public var promptPreferences: PromptPreferences {
        PromptPreferences(
            mealsPerDay: mealsPerDay, maxPrepMinutes: maxPrepMinutes, dailyBudgetEur: dailyBudgetEUR,
            excludedFoods: excludedFoods, likedFoods: likedFoods, equipment: equipment, batchCooking: batchCooking
        )
    }

    public func constraints(targets: MacroTotals) -> GenerationConstraints {
        GenerationConstraints(
            targets: targets, mealsPerDay: mealsPerDay, maxPrepMinutes: maxPrepMinutes,
            dailyBudgetEur: dailyBudgetEUR, batchCooking: batchCooking, excludedFoods: excludedFoods
        )
    }
}
