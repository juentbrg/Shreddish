import Foundation

/// Variété jugée sur la composition, pas sur le nom (spec 010) : l'IA renomme volontiers le même plat
/// (« Pâtes au thon et tomate », « Thon à la tomate avec pâtes »).
public enum VarietyCheck {
    public static let maxRepeats = 2

    /// Signature d'un plat : premier mot des aliments énergétiques d'au moins 30 g (protéine, féculent),
    /// légumes et matières grasses ignorés. « Poulet, riz et légumes » → ["poulet", "riz"].
    public static func signature(_ meal: MealDTO, catalog: FoodCatalog = .shared) -> [String] {
        let words = meal.ingredients.compactMap { ingredient -> String? in
            guard (ingredient.grams ?? 0) >= 30 else { return nil }
            let name: String
            if let code = ingredient.foodCode, let food = catalog.food(code: code) {
                guard food.per100g.kcal >= 60, food.per100g.fatG < 50 else { return nil }
                name = food.name
            } else {
                name = ingredient.name
            }
            return FoodMatcher.tokens(name).first
        }
        return Array(Set(words)).sorted()
    }

    /// Jours dont un déjeuner ou un dîner reprend une composition déjà présente `maxRepeats` fois
    /// (dans l'ordre des jours ; batch cooking exclu), avec les compositions en cause.
    public static func repeatedDays(_ days: [DayPlanDTO], catalog: FoodCatalog = .shared) -> [Int: [[String]]] {
        var seen: [[String]: Int] = [:]
        var repeated: [Int: [[String]]] = [:]
        for day in days.sorted(by: { $0.dayOffset < $1.dayOffset }) {
            for meal in day.meals where [.lunch, .dinner].contains(meal.type) && meal.prepSessionRef == nil {
                let signature = signature(meal, catalog: catalog)
                guard !signature.isEmpty else { continue }
                seen[signature, default: 0] += 1
                if seen[signature, default: 0] > maxRepeats { repeated[day.dayOffset, default: []].append(signature) }
            }
        }
        return repeated
    }
}
