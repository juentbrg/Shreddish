import Foundation

/// Fruits et légumes qui se gardent mal une fois entamés (avocat, banane…) : jamais quelques grammes, toujours
/// par moitié de pièce au moins (kiwi entier). Quantités arrondies avant l'ajustement des portions, puis fixes.
public enum WholeProduce {
    struct Rule {
        /// Poids d'une pièce entière en g, pour un produit vendu au poids ; sinon celui du produit.
        var wholeG: Double?
        /// Plus petite part : ½ ou 1 pièce.
        var step: Double
    }

    /// Par identifiant de produit (`prices.json`).
    static let rules: [String: Rule] = [
        "avocat": Rule(step: 0.5), "banane": Rule(step: 0.5), "pomme": Rule(step: 0.5), "poire": Rule(step: 0.5),
        "orange": Rule(step: 0.5), "kiwi": Rule(step: 1), "citron": Rule(step: 0.5),
        "courgette": Rule(wholeG: 250, step: 0.5), "poivron": Rule(wholeG: 150, step: 0.5),
        "oignon": Rule(wholeG: 100, step: 0.5), "aubergine": Rule(wholeG: 300, step: 0.5),
        "concombre": Rule(wholeG: 300, step: 0.5),
    ]

    /// Formes transformées vendues autrement qu'à la pièce (oignon séché, zeste, jus) : quantité libre.
    static let processed = ["seche", "deshydrate", "zeste", "vinaigre", "jus", "confit", "sirop", "poudre", "chips", "frit",
                            "puree", "compote", "surgele", "congele", "conserve", "appertise"]

    static func isProcessed(_ ingredient: IngredientDTO) -> Bool {
        let names = [ingredient.name] + [ingredient.foodCode.flatMap { FoodCatalog.shared.food(code: $0)?.name }].compactMap(\.self)
        return names.contains { name in processed.contains { TextNormalizer.containsWords(name, $0) } }
    }

    /// g mangeables d'une pièce et plus petite part, pour un ingrédient concerné.
    static func portion(for ingredient: IngredientDTO, catalog: PriceCatalog = .shared) -> (edibleG: Double, step: Double)? {
        guard !isProcessed(ingredient), let link = catalog.purchase(for: ingredient), let rule = rules[link.product.id],
              let whole = rule.wholeG ?? link.product.pieceG, whole > 0 else { return nil }
        // Sans code Ciqual : part mangeable de l'aliment tel qu'acheté (peau, noyau).
        let yield = ingredient.foodCode == nil
            ? catalog.purchasedFood(productId: link.product.id)?.edibleYield ?? 1 : link.edibleYield
        return (whole * min(yield, 1), rule.step)
    }

    public static func isWhole(_ ingredient: IngredientDTO) -> Bool { portion(for: ingredient) != nil }

    /// Nombre de pièces (par pas de ½) d'un ingrédient concerné ; `nil` sinon.
    public static func pieces(of ingredient: IngredientDTO) -> Double? {
        guard let portion = portion(for: ingredient) else { return nil }
        let count: Double = switch ingredient.measureUnit {
        case .piece: ingredient.quantity
        case .g, .ml: ingredient.quantity / portion.edibleG
        case nil: 0
        }
        return max(portion.step, (count / portion.step).rounded() * portion.step)
    }

    /// Quantité ramenée à la part la plus proche, au moins une part ; prix recalculé.
    public static func snapped(_ ingredient: IngredientDTO) -> IngredientDTO {
        guard let portion = portion(for: ingredient), let pieces = pieces(of: ingredient) else { return ingredient }
        var ingredient = ingredient
        switch ingredient.measureUnit {
        case .piece: ingredient.quantity = pieces
        case .g, .ml: ingredient.quantity = (pieces * portion.edibleG).rounded()
        case nil: return ingredient
        }
        AIOutputValidator.applyUnitPrice(&ingredient)
        return ingredient
    }

    /// Repas aux parts arrondies ; macros à recalculer par l'appelant si une quantité a changé.
    public static func snap(_ meal: MealDTO) -> MealDTO {
        var meal = meal
        meal.ingredients = meal.ingredients.map(snapped)
        return meal
    }
}
