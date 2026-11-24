import Foundation

/// Ligne agrégée de la liste de courses (FR-015).
public struct ShoppingLine: Sendable, Equatable {
    /// Identité stable pour conserver les coches : identifiant du produit acheté (spec 012), sinon nom
    /// normalisé, puis unité.
    public var key: String
    public var name: String
    /// Quantité à acheter dans l'unité d'achat, ingrédients à écouler déduits (spec 013).
    public var totalQuantity: Double
    public var unit: MeasureUnit
    public var aisle: Aisle
    /// Prix payé en caisse : paquets entiers (spec 013).
    public var costEur: Double
    /// Quantité couverte par les ingrédients à écouler.
    public var fromPantry: Double = 0
}

/// Achat d'une ligne : paquets entiers et reste (spec 013).
public struct Packing: Sendable, Equatable {
    /// Taille d'un paquet dans l'unité d'achat ; `nil` au détail.
    public var packSize: Double?
    public var packCount: Int
    /// Quantité achetée.
    public var bought: Double
    /// Reste après la semaine.
    public var leftover: Double
    /// Le reste se perd (produit frais ou conserve ouverte).
    public var perishable: Bool
    /// Valeur du reste ; 0 si prix inconnu.
    public var leftoverValue: Double
}

/// Ticket estimé de la semaine (spec 013).
public struct ShoppingSummary: Sendable, Equatable {
    /// Prix payé en caisse.
    public var checkoutEur: Double
    /// Restes qui se gardent (riz, huile, œufs) : non dépensés cette semaine.
    public var keptEur: Double
    /// Restes qui se perdent (fin de conserve, barquette entamée).
    public var wastedEur: Double

    /// Coût réel de la semaine : ticket moins ce qui reste pour les suivantes.
    public var weekCostEur: Double { max(0, checkoutEur - keptEur) }
}

public enum ShoppingListBuilder {
    /// Sachets de surgelés courants, pour la version surgelée d'un produit frais.
    static let frozenPacks: [Double] = [750, 1000]

    public static func normalize(_ name: String) -> String {
        TextNormalizer.singular(name)
    }

    public static func key(name: String, unit: MeasureUnit) -> String {
        "\(normalize(name))|\(unit.rawValue)"
    }

    public static func build(
        from days: [DayPlanDTO], owned: [String] = [], pantry: [IngredientDTO] = [], prices: PriceCatalog = .shared
    ) -> [ShoppingLine] {
        build(from: days.flatMap { $0.meals.flatMap(\.ingredients) }, owned: owned, pantry: pantry, prices: prices)
    }

    /// Une ligne par produit acheté (riz cru et cuit, œufs crus et durs, huile en g et en ml), dans l'unité
    /// d'achat du produit : g mangés ramenés au poids acheté (part comestible, cuisson), pièces entières pour
    /// les œufs et les fruits (spec 012). Ingrédients à écouler déduits, prix en paquets entiers (spec 013).
    /// Sans produit connu : fusion par nom, g et ml confondus. Tri par rayon puis nom ; unités invalides et
    /// compléments possédés (spec 004) ignorés.
    public static func build(
        from ingredients: [IngredientDTO], owned: [String] = [], pantry: [IngredientDTO] = [],
        prices: PriceCatalog = .shared
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
        for item in pantry {
            guard let stock = purchase(of: item, prices: prices), var line = lines[stock.key] else { continue }
            let used = min(line.totalQuantity, stock.totalQuantity)
            line.fromPantry += used
            line.totalQuantity -= used
            lines[stock.key] = line
        }
        return order.compactMap { lines[$0] }.map { priced($0, prices: prices) }.sorted {
            if $0.aisle != $1.aisle { return $0.aisle.sortIndex < $1.aisle.sortIndex }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Quantité achetée pour un ingrédient, avant fusion ; `nil` pour une unité invalide. `costEur` : coût
    /// de la quantité mangée, remplacé par le prix des paquets dans `priced`.
    static func purchase(of ingredient: IngredientDTO, prices: PriceCatalog) -> ShoppingLine? {
        guard let unit = ingredient.measureUnit else { return nil }
        if let link = prices.purchase(for: ingredient), let quantity = purchasedQuantity(ingredient, link: link) {
            let product = link.product
            let unitKey = product.unit == .ml ? MeasureUnit.g : product.unit
            // Version surgelée d'un produit frais (« haricots verts surgelés ») : ligne à part, au rayon surgelés.
            // Produit à la pièce (banane) : acheté frais, jamais en sachet surgelé.
            if product.aisle != .surgeles, product.unit != .piece, AisleClassifier.inferred(ingredient.name) == .surgeles {
                return ShoppingLine(
                    key: "\(product.id)\(frozenSuffix)|\(unitKey.rawValue)", name: displayName(ingredient.name),
                    totalQuantity: quantity, unit: product.unit, aisle: .surgeles, costEur: ingredient.costEur
                )
            }
            return ShoppingLine(
                key: "\(product.id)|\(unitKey.rawValue)", name: product.label,
                totalQuantity: quantity, unit: product.unit, aisle: product.aisle, costEur: ingredient.costEur
            )
        }
        return ShoppingLine(
            key: key(name: ingredient.name, unit: unit == .ml ? .g : unit), name: displayName(ingredient.name),
            totalQuantity: ingredient.quantity, unit: unit,
            aisle: AisleClassifier.corrected(name: ingredient.name, aisle: ingredient.aisle), costEur: ingredient.costEur
        )
    }

    private static let frozenSuffix = " surgele"

    /// Quantité dans l'unité d'achat du produit ; `nil` si une pièce sans poids empêche la conversion.
    private static func purchasedQuantity(_ ingredient: IngredientDTO, link: PurchaseLink) -> Double? {
        let product = link.product
        if product.unit == .piece, ingredient.measureUnit == .piece { return ingredient.quantity }
        guard let grams = ingredient.grams else { return nil }
        let bought = grams / link.edibleYield
        guard product.unit == .piece else { return bought }
        return product.pieceG.map { bought / $0 }
    }

    /// Quantité arrondie (pièces entières avec une marge : 1,1 avocat → 1 ; g et ml à l'unité) et prix en
    /// caisse : paquets entiers au prix de la table, sinon coût mangé ramené à la quantité achetée.
    private static func priced(_ line: ShoppingLine, prices: PriceCatalog) -> ShoppingLine {
        var line = line
        let eaten = line.costEur
        let needed = line.totalQuantity + line.fromPantry
        line.totalQuantity = rounded(line.totalQuantity, unit: line.unit)
        line.fromPantry = rounded(line.fromPantry, unit: line.unit)
        let packing = packing(key: line.key, quantity: line.totalQuantity, unit: line.unit, prices: prices)
        if let product = product(forKey: line.key, prices: prices), let cost = product.cost(of: packing.bought) {
            line.costEur = BudgetMath.cents(cost)
        } else {
            line.costEur = needed > 0 ? BudgetMath.cents(eaten * packing.bought / needed) : 0
        }
        return line
    }

    private static func rounded(_ quantity: Double, unit: MeasureUnit) -> Double {
        guard quantity > 0.005 else { return 0 }
        return unit == .piece ? max(1, (quantity - 0.15).rounded(.up)) : quantity.rounded()
    }

    /// Produit d'une ligne d'après sa clé, dans la même unité d'achat (« oignon|piece » sans code n'est pas le
    /// produit « oignon » vendu au poids). Version surgelée : prix du frais plafonné à celui des légumes surgelés.
    static func product(forKey key: String, prices: PriceCatalog) -> PurchaseProduct? {
        let parts = key.split(separator: "|").map(String.init)
        guard let id = parts.first else { return nil }
        let frozen = id.hasSuffix(frozenSuffix)
        guard let product = prices.product(id: frozen ? String(id.dropLast(frozenSuffix.count)) : id) else { return nil }
        let unitKey = product.unit == .ml ? MeasureUnit.g : product.unit
        guard parts.count < 2 || parts[1] == unitKey.rawValue else { return nil }
        guard frozen, let fresh = product.price, let bag = prices.product(id: frozenVegetablesId)?.price, bag < fresh else {
            return product
        }
        return PurchaseProduct(
            id: product.id, label: product.label, unit: product.unit, pieceG: product.pieceG, aisle: .surgeles,
            price: bag, packs: product.packs, perishable: product.perishable
        )
    }

    /// Légumes surgelés en sachet (prix au kg des versions surgelées).
    private static let frozenVegetablesId = "legumes surgeles"

    /// Paquets à acheter pour une ligne : la combinaison d'un seul format qui laisse le moins de reste, puis le
    /// moins de paquets ; au détail sans format connu.
    public static func packing(
        key: String, quantity: Double, unit: MeasureUnit, prices: PriceCatalog = .shared
    ) -> Packing {
        let product = product(forKey: key, prices: prices)
        let frozen = key.split(separator: "|").first?.hasSuffix(frozenSuffix) ?? false
        let sizes = frozen ? frozenPacks : product?.packs ?? []
        let perishable = !frozen && product?.perishable == true
        guard quantity > 0, !sizes.isEmpty else {
            return Packing(packSize: nil, packCount: 0, bought: quantity, leftover: 0, perishable: perishable, leftoverValue: 0)
        }
        let best = sizes.map { size in (size: size, count: Int((quantity / size - 1e-6).rounded(.up))) }
            .min { lhs, rhs in
                let left = Double(lhs.count) * lhs.size
                let right = Double(rhs.count) * rhs.size
                return left != right ? left < right : lhs.count < rhs.count
            } ?? (size: quantity, count: 1)
        let bought = Double(best.count) * best.size
        let leftover = bought - quantity
        return Packing(
            packSize: best.size, packCount: best.count, bought: bought, leftover: leftover, perishable: perishable,
            leftoverValue: product?.cost(of: leftover) ?? 0
        )
    }

    /// Ticket estimé : prix en caisse, restes qui se gardent et restes perdus.
    public static func summary(_ lines: [ShoppingLine], prices: PriceCatalog = .shared) -> ShoppingSummary {
        var summary = ShoppingSummary(checkoutEur: 0, keptEur: 0, wastedEur: 0)
        for line in lines {
            summary.checkoutEur += line.costEur
            let packing = packing(key: line.key, quantity: line.totalQuantity, unit: line.unit, prices: prices)
            if packing.perishable { summary.wastedEur += packing.leftoverValue } else { summary.keptEur += packing.leftoverValue }
        }
        return summary
    }

    /// Restes d'une liste (paquets entamés), en quantité mangeable avec leur code Ciqual : suggestions
    /// d'ingrédients à écouler pour la semaine suivante (spec 013).
    public static func leftovers(_ lines: [ShoppingLine], prices: PriceCatalog = .shared) -> [IngredientDTO] {
        lines.compactMap { line in
            let packing = packing(key: line.key, quantity: line.totalQuantity, unit: line.unit, prices: prices)
            guard packing.leftover >= (line.unit == .piece ? 1 : 10), let product = product(forKey: line.key, prices: prices),
                  let food = prices.purchasedFood(productId: product.id) else { return nil }
            let quantity = line.unit == .piece ? packing.leftover : (packing.leftover * food.edibleYield).rounded()
            return IngredientDTO(
                name: line.name, quantity: quantity, unit: line.unit.rawValue, aisle: product.aisle, costEur: 0,
                pieceG: product.pieceG, foodCode: food.code
            )
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
