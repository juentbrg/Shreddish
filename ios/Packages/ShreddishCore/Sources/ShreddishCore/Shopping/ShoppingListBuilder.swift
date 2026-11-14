import Foundation

/// Ligne agrégée de la liste de courses (FR-015).
public struct ShoppingLine: Sendable, Equatable {
    /// Nom normalisé + unité : identité stable pour conserver les coches.
    public var key: String
    public var name: String
    public var totalQuantity: Double
    public var unit: MeasureUnit
    public var aisle: Aisle
    public var costEur: Double
}

public enum ShoppingListBuilder {
    public static func normalize(_ name: String) -> String {
        TextNormalizer.singular(name)
    }

    public static func key(name: String, unit: MeasureUnit) -> String {
        "\(normalize(name))|\(unit.rawValue)"
    }

    public static func build(
        from days: [DayPlanDTO], owned: [String] = [], prices: PriceCatalog = .shared
    ) -> [ShoppingLine] {
        build(from: days.flatMap { $0.meals.flatMap(\.ingredients) }, owned: owned, prices: prices)
    }

    /// Une ligne par produit acheté (riz cru et cuit, œufs crus et durs, huile en g et en ml), dans l'unité
    /// d'achat du produit : g mangés ramenés au poids acheté (part comestible, cuisson), pièces entières pour
    /// les œufs et les fruits (spec 012). Sans produit connu : fusion par nom, g et ml confondus. Tri par rayon
    /// puis nom ; unités invalides et compléments possédés (spec 004) ignorés.
    public static func build(
        from ingredients: [IngredientDTO], owned: [String] = [], prices: PriceCatalog = .shared
    ) -> [ShoppingLine] {
        var lines: [String: ShoppingLine] = [:]
        var order: [String] = []
        for ingredient in ingredients where !AIOutputValidator.isOwnedSupplement(ingredient.name, owned: owned) {
            guard let purchase = purchase(of: ingredient, prices: prices) else { continue }
            if var line = lines[purchase.key] {
                line.totalQuantity += purchase.totalQuantity
                line.costEur += purchase.costEur
                if purchase.unit == .ml { line.unit = .ml }
                lines[purchase.key] = line
            } else {
                order.append(purchase.key)
                lines[purchase.key] = purchase
            }
        }
        return order.compactMap { lines[$0] }.map(rounded).sorted {
            if $0.aisle != $1.aisle { return $0.aisle.sortIndex < $1.aisle.sortIndex }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Quantité achetée pour un ingrédient, avant fusion ; `nil` pour une unité invalide.
    static func purchase(of ingredient: IngredientDTO, prices: PriceCatalog) -> ShoppingLine? {
        guard let unit = ingredient.measureUnit else { return nil }
        if let link = prices.purchase(for: ingredient), let quantity = purchasedQuantity(ingredient, link: link) {
            let product = link.product
            return ShoppingLine(
                key: key(name: product.label, unit: product.unit == .ml ? .g : product.unit), name: product.label,
                totalQuantity: quantity, unit: product.unit, aisle: product.aisle, costEur: ingredient.costEur
            )
        }
        return ShoppingLine(
            key: key(name: ingredient.name, unit: unit == .ml ? .g : unit), name: displayName(ingredient.name),
            totalQuantity: ingredient.quantity, unit: unit,
            aisle: AisleClassifier.corrected(name: ingredient.name, aisle: ingredient.aisle), costEur: ingredient.costEur
        )
    }

    /// Quantité dans l'unité d'achat du produit ; `nil` si une pièce sans poids empêche la conversion.
    private static func purchasedQuantity(_ ingredient: IngredientDTO, link: PurchaseLink) -> Double? {
        let product = link.product
        if product.unit == .piece, ingredient.measureUnit == .piece { return ingredient.quantity }
        guard let grams = ingredient.grams else { return nil }
        let bought = grams / link.edibleYield
        guard product.unit == .piece else { return bought }
        return product.pieceG.map { bought / $0 }
    }

    /// Pièces entières, arrondies au-dessus avec une marge (1,1 avocat → 1) ; g et ml à l'unité.
    private static func rounded(_ line: ShoppingLine) -> ShoppingLine {
        var line = line
        line.totalQuantity = line.unit == .piece
            ? max(1, (line.totalQuantity - 0.15).rounded(.up)) : line.totalQuantity.rounded()
        return line
    }

    public static func totalCost(_ lines: [ShoppingLine]) -> Double {
        lines.reduce(0) { $0 + $1.costEur }
    }

    private static func displayName(_ name: String) -> String {
        let trimmed = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }
}
