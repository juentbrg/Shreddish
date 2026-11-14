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

/// Produit acheté en magasin auquel se rattachent un ou plusieurs aliments Ciqual (riz cru et cuit, œuf cru
/// et dur) : la liste de courses fusionne par produit, dans son unité d'achat (spec 012).
public struct PurchaseProduct: Sendable, Equatable {
    public let id: String
    public let label: String
    /// g, ml, ou pièce (œufs, fruits).
    public let unit: MeasureUnit
    /// Poids d'une pièce entière en g, pour l'unité pièce.
    public let pieceG: Double?
    public let aisle: Aisle

    public init(id: String, label: String, unit: MeasureUnit = .g, pieceG: Double? = nil, aisle: Aisle = .autre) {
        self.id = id
        self.label = label
        self.unit = unit
        self.pieceG = pieceG
        self.aisle = aisle
    }
}

/// Aliment rattaché à son produit : `edibleYield` g mangés par g acheté (peau, cuisson).
public struct PurchaseLink: Sendable, Equatable {
    public let product: PurchaseProduct
    public let edibleYield: Double
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
    let links: [Int: PurchaseLink]
    /// Produits par libellé ou identifiant normalisé, pour les ingrédients sans code Ciqual.
    let productsByName: [String: PurchaseProduct]

    public init(
        prices: [Int: FoodPrice], groupRanges: [Int: ClosedRange<Double>] = [:], links: [Int: PurchaseLink] = [:]
    ) {
        self.prices = prices
        self.groupRanges = groupRanges
        self.links = links
        var byName: [String: PurchaseProduct] = [:]
        for product in links.values.map(\.product) {
            byName[TextNormalizer.singular(product.label)] = product
            byName[TextNormalizer.singular(product.id)] = product
        }
        productsByName = byName
    }

    convenience init(json: Data) throws {
        struct File: Decodable {
            let foods: [String: [JSONCell]]
            let groups: [String: [Double]]
            let products: [String: [JSONCell]]?
        }
        let file = try JSONDecoder().decode(File.self, from: json)
        var products: [String: PurchaseProduct] = [:]
        for (id, row) in file.products ?? [:] { products[id] = Self.product(id: id, row: row) }
        var prices: [Int: FoodPrice] = [:]
        var links: [Int: PurchaseLink] = [:]
        for (code, row) in file.foods {
            guard let code = Int(code) else { continue }
            let yield = row.count > 1 ? row[1].number ?? 1 : 1
            if let price = row.first?.number { prices[code] = FoodPrice(eurPerKg: price, edibleYield: yield) }
            if row.count > 2, let product = row[2].text.flatMap({ products[$0] }), yield > 0 {
                links[code] = PurchaseLink(product: product, edibleYield: yield)
            }
        }
        var ranges: [Int: ClosedRange<Double>] = [:]
        for (group, row) in file.groups {
            guard let group = Int(group), row.count == 2, row[0] <= row[1] else { continue }
            ranges[group] = row[0]...row[1]
        }
        self.init(prices: prices, groupRanges: ranges, links: links)
    }

    /// Ligne `products` (libellé, unité d'achat, poids d'une pièce, rayon) ; `nil` si invalide.
    private static func product(id: String, row: [JSONCell]) -> PurchaseProduct? {
        guard row.count == 4, let label = row[0].text, let unit = row[1].text.flatMap(MeasureUnit.init(rawValue:)) else {
            return nil
        }
        let pieceG = row[2].number.flatMap { $0 > 0 ? $0 : nil }
        guard unit != .piece || pieceG != nil else { return nil }
        let aisle = row[3].text.flatMap(Aisle.init(rawValue:)) ?? .autre
        return PurchaseProduct(id: id, label: label, unit: unit, pieceG: pieceG, aisle: aisle)
    }

    public func price(code: Int) -> FoodPrice? { prices[code] }

    /// Produit acheté : par code Ciqual, sinon par nom exact (« Œufs », « avocat ») pour les plans sans code.
    public func purchase(for ingredient: IngredientDTO) -> PurchaseLink? {
        if let code = ingredient.foodCode { return links[code] }
        return productsByName[TextNormalizer.singular(ingredient.name)].map { PurchaseLink(product: $0, edibleYield: 1) }
    }

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

/// Cellule d'une ligne de `prices.json` : nombre, texte ou null.
enum JSONCell: Decodable {
    case number(Double), text(String), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    var number: Double? { if case let .number(value) = self { value } else { nil } }
    var text: String? { if case let .text(value) = self { value } else { nil } }
}
