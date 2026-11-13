import Foundation

/// Prix de référence d'un aliment Ciqual (spec 011).
public struct FoodPrice: Sendable, Equatable {
    /// € par kg acheté (par litre pour un liquide).
    public let eurPerKg: Double
    /// g mangés par g acheté (peau, noyau, jus d'une conserve) ; > 1 pour un aliment cuit qui gonfle.
    public let edibleYield: Double

    public init(eurPerKg: Double, edibleYield: Double = 1) {
        self.eurPerKg = eurPerKg
        self.edibleYield = edibleYield
    }

    /// € par kg mangé.
    public var eurPerEdibleKg: Double { edibleYield > 0 ? eurPerKg / edibleYield : eurPerKg }
}

/// Prix France (quartile bas des relevés Open Prices, licence ODbL) par code Ciqual, générés par
/// `tools/prices/build_prices.py`. Les prix de l'IA ne servent qu'aux aliments absents, bornés par groupe.
public final class PriceCatalog: Sendable {
    public static let attribution = "Prix : relevés Open Prices (Open Food Facts), licence ODbL."

    public static let shared: PriceCatalog = {
        guard let url = Bundle.module.url(forResource: "prices", withExtension: "json"),
              let data = try? Data(contentsOf: url), let catalog = try? PriceCatalog(json: data) else {
            return PriceCatalog(prices: [:])
        }
        return catalog
    }()

    let prices: [Int: FoodPrice]
    /// Fourchette de prix au kg par groupe Ciqual (10e et 90e centiles de la table).
    let groupRanges: [Int: ClosedRange<Double>]

    public init(prices: [Int: FoodPrice], groupRanges: [Int: ClosedRange<Double>] = [:]) {
        self.prices = prices
        self.groupRanges = groupRanges
    }

    convenience init(json: Data) throws {
        struct File: Decodable {
            let foods: [String: [Double]]
            let groups: [String: [Double]]
        }
        let file = try JSONDecoder().decode(File.self, from: json)
        var prices: [Int: FoodPrice] = [:]
        for (code, row) in file.foods {
            guard let code = Int(code), let price = row.first else { continue }
            prices[code] = FoodPrice(eurPerKg: price, edibleYield: row.count > 1 ? row[1] : 1)
        }
        var ranges: [Int: ClosedRange<Double>] = [:]
        for (group, row) in file.groups {
            guard let group = Int(group), row.count == 2, row[0] <= row[1] else { continue }
            ranges[group] = row[0]...row[1]
        }
        self.init(prices: prices, groupRanges: ranges)
    }

    public func price(code: Int) -> FoodPrice? { prices[code] }

    /// Prix unitaire dans l'unité de l'ingrédient (€/kg, €/L ou €/pièce) : prix de la table, sinon prix de
    /// l'IA ramené dans la fourchette du groupe ; `nil` si rien n'est connu.
    public func unitPrice(for ingredient: IngredientDTO, group: Int?) -> Double? {
        guard let unit = ingredient.measureUnit else { return ingredient.unitPriceEur }
        if let code = ingredient.foodCode, let price = prices[code] {
            switch unit {
            case .g, .ml: return BudgetMath.cents(price.eurPerEdibleKg)
            case .piece:
                // Poids d'une pièce entière : prix au kg acheté, sans part comestible.
                guard let pieceG = ingredient.pieceG, pieceG > 0 else { return ingredient.unitPriceEur }
                return BudgetMath.cents(price.eurPerKg * pieceG / 1000)
            }
        }
        guard let aiPrice = ingredient.unitPriceEur, unit != .piece, let group, let range = groupRanges[group] else {
            return ingredient.unitPriceEur
        }
        return min(max(aiPrice, range.lowerBound), range.upperBound)
    }
}
