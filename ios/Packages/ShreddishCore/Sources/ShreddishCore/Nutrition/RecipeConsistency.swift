import Foundation

/// Étapes rédigées pour d'autres quantités que celles du repas (portions ajustées après coup) : à réécrire.
public enum RecipeConsistency {
    /// Chaque ingrédient en g ou ml (5 g et plus) est cité avec sa quantité exacte dans les étapes ;
    /// fruits et légumes par moitié cités en pièces, non vérifiés.
    public static func stepsMatch(_ meal: MealDTO) -> Bool {
        guard !meal.steps.isEmpty else { return true }
        let text = meal.steps.joined(separator: " ").replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        return meal.ingredients.allSatisfy { ingredient in
            guard let unit = ingredient.measureUnit, unit != .piece, ingredient.quantity >= 5,
                  !WholeProduce.isWhole(ingredient) else { return true }
            let symbol = unit == .ml ? "ml" : "g"
            return spellings(ingredient.quantity).contains { number in
                text.contains("\(number) \(symbol)") || text.contains("\(number)\(symbol)")
            }
        }
    }

    /// « 52,5 » et « 52.5 », ou « 70 ».
    static func spellings(_ quantity: Double) -> [String] {
        if quantity == quantity.rounded() { return [String(Int(quantity))] }
        let dotted = String(format: "%g", quantity)
        return [dotted, dotted.replacingOccurrences(of: ".", with: ",")]
    }
}
