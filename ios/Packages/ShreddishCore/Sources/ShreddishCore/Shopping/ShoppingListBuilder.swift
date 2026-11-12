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

    public static func build(from days: [DayPlanDTO], owned: [String] = []) -> [ShoppingLine] {
        build(from: days.flatMap { $0.meals.flatMap(\.ingredients) }, owned: owned)
    }

    /// Fusion par (nom normalisé, unité), tri par rayon puis nom. Unités invalides et compléments
    /// possédés (spec 004) ignorés.
    public static func build(from ingredients: [IngredientDTO], owned: [String] = []) -> [ShoppingLine] {
        var lines: [String: ShoppingLine] = [:]
        var order: [String] = []
        for ingredient in ingredients where !AIOutputValidator.isOwnedSupplement(ingredient.name, owned: owned) {
            guard let unit = ingredient.measureUnit else { continue }
            let key = key(name: ingredient.name, unit: unit)
            if var line = lines[key] {
                line.totalQuantity += ingredient.quantity
                line.costEur += ingredient.costEur
                lines[key] = line
            } else {
                order.append(key)
                lines[key] = ShoppingLine(
                    key: key, name: displayName(ingredient.name), totalQuantity: ingredient.quantity,
                    unit: unit, aisle: ingredient.aisle, costEur: ingredient.costEur
                )
            }
        }
        return order.compactMap { lines[$0] }.sorted {
            if $0.aisle != $1.aisle { return $0.aisle.sortIndex < $1.aisle.sortIndex }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public static func totalCost(_ lines: [ShoppingLine]) -> Double {
        lines.reduce(0) { $0 + $1.costEur }
    }

    private static func displayName(_ name: String) -> String {
        let trimmed = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }
}
