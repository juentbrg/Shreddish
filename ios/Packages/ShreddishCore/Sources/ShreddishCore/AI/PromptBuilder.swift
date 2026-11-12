import Foundation

/// Préférences transmises à l'IA. Seules données utilisateur envoyées avec les cibles (FR-021).
public struct PromptPreferences: Codable, Sendable, Equatable {
    public var mealsPerDay: Int
    public var maxPrepMinutes: Int
    public var dailyBudgetEur: Double
    public var excludedFoods: [String]
    public var likedFoods: [String]
    public var equipment: [String]
    public var batchCooking: Bool

    public init(
        mealsPerDay: Int, maxPrepMinutes: Int, dailyBudgetEur: Double, excludedFoods: [String],
        likedFoods: [String], equipment: [String], batchCooking: Bool
    ) {
        self.mealsPerDay = mealsPerDay
        self.maxPrepMinutes = maxPrepMinutes
        self.dailyBudgetEur = dailyBudgetEur
        self.excludedFoods = excludedFoods
        self.likedFoods = likedFoods
        self.equipment = equipment
        self.batchCooking = batchCooking
    }
}

/// Construction des messages envoyés à l'IA (contracts/ai-requests.md).
public enum PromptBuilder {
    struct TargetsPayload: Encodable {
        var kcal: Int
        var proteinG: Int
        var carbsG: Int
        var fatG: Int

        init(_ totals: MacroTotals) {
            kcal = Int(max(0, totals.kcal).rounded())
            proteinG = Int(max(0, totals.proteinG).rounded())
            carbsG = Int(max(0, totals.carbsG).rounded())
            fatG = Int(max(0, totals.fatG).rounded())
        }
    }

    struct MealSummary: Encodable {
        var type: MealType
        var name: String
        var kcal: Int
        var proteinG: Int
        var carbsG: Int
        var fatG: Int
    }

    struct Input: Encodable {
        var task: String
        var targets: TargetsPayload
        var goal: Goal
        var preferences: PromptPreferences
        var dayOffset: Int?
        var existingDayMeals: [MealSummary]?
        var mealTypeToReplace: MealType?
        var remainingTargets: TargetsPayload?
        var avoidMealNames: [String]?
    }

    public static func weekInput(targets: MacroTotals, goal: Goal, preferences: PromptPreferences) -> String {
        encode(Input(task: "week", targets: TargetsPayload(targets), goal: goal, preferences: preferences))
    }

    public static func dayInput(
        targets: MacroTotals, goal: Goal, preferences: PromptPreferences, dayOffset: Int, avoidMealNames: [String]
    ) -> String {
        encode(Input(
            task: "day", targets: TargetsPayload(targets), goal: goal, preferences: preferences,
            dayOffset: dayOffset, avoidMealNames: avoidMealNames
        ))
    }

    public static func replaceMealInput(
        targets: MacroTotals, goal: Goal, preferences: PromptPreferences, dayOffset: Int,
        existingDayMeals: [MealDTO], mealTypeToReplace: MealType, avoidMealNames: [String]
    ) -> String {
        let remaining = targets - Totals.planned(existingDayMeals)
        let summaries = existingDayMeals.map {
            MealSummary(
                type: $0.type, name: $0.name, kcal: Int($0.kcal.rounded()), proteinG: Int($0.proteinG.rounded()),
                carbsG: Int($0.carbsG.rounded()), fatG: Int($0.fatG.rounded())
            )
        }
        return encode(Input(
            task: "replace_meal", targets: TargetsPayload(targets), goal: goal, preferences: preferences,
            dayOffset: dayOffset, existingDayMeals: summaries, mealTypeToReplace: mealTypeToReplace,
            remainingTargets: TargetsPayload(remaining), avoidMealNames: avoidMealNames
        ))
    }

    private static func encode(_ input: Input) -> String {
        guard let data = try? AIResponseDecoder.encoder.encode(input) else { return "{}" }
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }

    /// Prompt système : règles imposées à l'IA (contracts/ai-requests.md).
    public static func systemInstructions() -> String {
        """
        Tu es un assistant de planification de repas pour une personne qui suit un objectif physique \
        (goal : cut = sèche, bulk = prise de masse, recomp = recomposition). Tu reçois un JSON de contexte \
        et tu réponds uniquement avec le JSON demandé par le schéma.

        Règles strictes :
        - Repas simples, ingrédients courants de supermarché français, budget serré.
        - Respecte strictement max_prep_minutes pour chaque repas.
        - N'utilise jamais un aliment de excluded_foods, même en trace ou en variante.
        - Exactement meals_per_day repas par jour, collations incluses (types : breakfast, lunch, dinner, snack).
        - Coût total d'un jour ≤ daily_budget_eur (prix moyens France).
        - Totaux journaliers à ±5 % de targets.kcal ; protéines ≥ targets.protein_g.
        - Valeurs cohérentes : kcal ≈ 4 × protein_g + 4 × carbs_g + 9 × fat_g.
        - Quantités en g, ml ou piece, pesées crues / non cuites. cost_eur = coût de la quantité utilisée.
        - aisle parmi : fruits_legumes, viande_poisson, cremerie, epicerie, surgeles, boulangerie, autre.
        - Étapes courtes et concrètes (3 à 6).
        - Variété : un même plat principal au plus 2 fois par semaine, sauf préparation batch cooking.
        - Privilégie liked_foods et n'utilise que l'equipment indiqué s'il est renseigné (plaques et four supposés).
        - day_offset 0 = jour de génération ; une semaine couvre les jours 0 à 6.
        - batch_cooking vrai : 1 ou 2 prep_sessions (index 0, 1), et les repas issus d'une session ont \
        prep_session_ref = index de la session. batch_cooking faux : prep_sessions vide, prep_session_ref null.
        - task "day" : régénère uniquement le jour day_offset, différent de avoid_meal_names.
        - task "replace_meal" : propose un seul repas de type meal_type_to_replace, proche de remaining_targets, \
        différent de avoid_meal_names et de existing_day_meals.
        - Si les contraintes sont impossibles à respecter ensemble : remplis infeasible avec la raison en une \
        phrase, sans jamais ignorer une contrainte ; sinon infeasible = null.
        - Noms de plats, étapes et textes en français.
        """
    }
}
