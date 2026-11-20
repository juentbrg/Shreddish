import Foundation
import SwiftData

/// Recette sauvegardée depuis un repas qui a plu, à replacer dans une semaine suivante (spec 014).
/// Copie du repas : survit à la suppression du planning.
@Model
public final class SavedRecipe {
    @Attribute(.unique) public var id: UUID
    public var typeRaw: String
    public var name: String
    /// `[IngredientDTO]` encodés.
    public var ingredientsData: Data
    public var steps: [String]
    public var prepMinutes: Int
    public var costEUR: Double
    public var kcal: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var savedAt: Date
    /// À replacer dans la prochaine semaine planifiée.
    public var isQueued: Bool

    public init(meal: MealDTO, savedAt: Date) {
        id = UUID()
        typeRaw = meal.type.rawValue
        name = meal.name
        ingredientsData = (try? JSONEncoder().encode(meal.ingredients)) ?? Data()
        steps = meal.steps
        prepMinutes = meal.prepMinutes
        costEUR = meal.costEur
        kcal = meal.kcal
        proteinG = meal.proteinG
        carbsG = meal.carbsG
        fatG = meal.fatG
        self.savedAt = savedAt
        isQueued = false
    }

    public var type: MealType { MealType(rawValue: typeRaw) ?? .lunch }

    /// Contenu remplacé par une recette modifiée (spec 017).
    public func apply(_ meal: MealDTO) {
        typeRaw = meal.type.rawValue
        name = meal.name
        ingredientsData = (try? JSONEncoder().encode(meal.ingredients)) ?? Data()
        steps = meal.steps
        prepMinutes = meal.prepMinutes
        costEUR = meal.costEur
        kcal = meal.kcal
        proteinG = meal.proteinG
        carbsG = meal.carbsG
        fatG = meal.fatG
    }

    public var ingredients: [IngredientDTO] {
        (try? JSONDecoder().decode([IngredientDTO].self, from: ingredientsData)) ?? []
    }

    public var dto: MealDTO {
        MealDTO(
            type: type, name: name, ingredients: ingredients, steps: steps, prepMinutes: prepMinutes, costEur: costEUR,
            kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG, prepSessionRef: nil, time: nil
        )
    }
}

/// Sauvegarde des recettes et reprise dans une semaine générée (spec 014).
@MainActor
public enum RecipeBook {
    /// Clé de rapprochement par nom.
    public static func key(_ name: String) -> String { TextNormalizer.singular(name) }

    public static func saved(named name: String, in context: ModelContext) -> SavedRecipe? {
        let key = key(name)
        return ((try? context.fetch(FetchDescriptor<SavedRecipe>())) ?? []).first { Self.key($0.name) == key }
    }

    /// Sauvegarde le repas, ou retire la recette déjà sauvegardée sous ce nom. Renvoie l'état final.
    @discardableResult
    public static func toggle(_ meal: MealDTO, at date: Date, in context: ModelContext) -> Bool {
        if let existing = saved(named: meal.name, in: context) {
            context.delete(existing)
            try? context.save()
            return false
        }
        context.insert(SavedRecipe(meal: meal, savedAt: date))
        try? context.save()
        return true
    }
}

public enum SavedRecipeMatcher {
    /// Reprend les étapes d'une recette sauvegardée quand l'IA l'a replacée telle quelle (mêmes ingrédients,
    /// quantités à ±10 %) ; sinon les étapes restent vides et sont rédigées pour les nouvelles quantités.
    public static func restoreSteps(_ days: [DayPlanDTO], recipes: [MealDTO]) -> [DayPlanDTO] {
        guard !recipes.isEmpty else { return days }
        let byKey = Dictionary(recipes.map { (TextNormalizer.singular($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        return days.map { day in
            var day = day
            day.meals = day.meals.map { meal in
                guard meal.steps.isEmpty, let recipe = byKey[TextNormalizer.singular(meal.name)], !recipe.steps.isEmpty,
                      sameIngredients(meal.ingredients, recipe.ingredients) else { return meal }
                var meal = meal
                meal.steps = recipe.steps
                return meal
            }
            return day
        }
    }

    static func sameIngredients(_ lhs: [IngredientDTO], _ rhs: [IngredientDTO]) -> Bool {
        func quantities(_ items: [IngredientDTO]) -> [String: Double] {
            Dictionary(items.map { ("\(TextNormalizer.singular($0.name))|\($0.unit)", $0.quantity) }, uniquingKeysWith: +)
        }
        let left = quantities(lhs)
        let right = quantities(rhs)
        guard Set(left.keys) == Set(right.keys) else { return false }
        return left.allSatisfy { key, value in
            guard let other = right[key], other > 0 else { return value == 0 }
            return abs(value / other - 1) <= 0.1
        }
    }

    /// Recettes d'un jour quand la semaine est demandée jour par jour : la n-ième recette au jour n mod 7.
    public static func recipes(_ recipes: [MealDTO], forDay offset: Int) -> [MealDTO] {
        recipes.enumerated().filter { $0.offset % 7 == offset }.map(\.element)
    }
}
