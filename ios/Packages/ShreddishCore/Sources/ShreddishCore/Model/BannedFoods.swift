import Foundation
import SwiftData

/// Aliments bannis : jamais proposés dans les plannings (liste « aliments exclus » des préférences).
extension Preferences {
    /// Ajoute un aliment aux exclus s'il n'y est pas déjà (comparaison sans accents ni pluriel). `true` si ajouté.
    @discardableResult
    public func ban(_ food: String) -> Bool {
        let name = food.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = TextNormalizer.singular(name)
        guard !key.isEmpty, !excludedFoods.contains(where: { TextNormalizer.singular($0) == key }) else { return false }
        excludedFoods.append(name)
        return true
    }

    public func isBanned(_ food: String) -> Bool {
        let key = TextNormalizer.singular(food)
        return !key.isEmpty && excludedFoods.contains { TextNormalizer.singular($0) == key }
    }
}

extension PlanStore {
    /// Repas à venir (aujourd'hui compris) des plannings actifs qui contiennent l'aliment.
    public static func upcomingMeals(containing food: String, from today: LocalDay, in context: ModelContext) -> [Meal] {
        upcomingMeals(containingAnyOf: [food], from: today, in: context)
    }

    /// Repas à venir (aujourd'hui compris), encore prévus, qui contiennent au moins un des aliments.
    public static func upcomingMeals(containingAnyOf foods: [String], from today: LocalDay, in context: ModelContext) -> [Meal] {
        guard !foods.isEmpty else { return [] }
        return activePlans(in: context)
            .flatMap(\.sortedDays)
            .filter { $0.day >= today }
            .flatMap(\.sortedMeals)
            .filter { $0.status == .planned && AIOutputValidator.excludedFood(in: $0.dto, excluded: foods) != nil }
    }
}
