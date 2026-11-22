import Foundation
import SwiftData

/// Ingrédients achetés mais pas mangés (repas sautés ou jamais cochés des jours passés, ex. cheat day) :
/// suggestions à écouler quand on régénère une journée. Seulement les `days` derniers jours (restes frais).
extension PlanStore {
    public static func uneatenIngredients(in plans: [WeeklyPlan], before today: LocalDay, days: Int = 3) -> [IngredientDTO] {
        var totals: [String: IngredientDTO] = [:]
        var order: [String] = []
        let meals = plans.flatMap(\.sortedDays)
            .filter { $0.day < today && $0.day >= today.adding(days: -days) }.flatMap(\.sortedMeals).filter { $0.status != .eaten }
        for ingredient in meals.flatMap(\.ingredients) {
            let key = "\(TextNormalizer.singular(ingredient.name))|\(ingredient.unit)"
            if var total = totals[key] {
                total.quantity += ingredient.quantity
                totals[key] = total
            } else {
                order.append(key)
                var item = ingredient
                item.costEur = 0
                totals[key] = item
            }
        }
        return order.compactMap { totals[$0] }.map { item in
            var item = item
            item.quantity = item.quantity.rounded()
            return item
        }
    }
}
