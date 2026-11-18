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
    /// Prix dans l'unité d'achat : € par kg (g), par litre (ml) ou par pièce ; `nil` si inconnu (spec 013).
    public let price: Double?
    /// Tailles de paquet vendues, dans l'unité d'achat (boîte de 400 g, boîte de 6 œufs) ; vide : au détail.
    public let packs: [Double]
    /// Se perd une fois ouvert (frais, conserve) : le reste d'un paquet est compté comme dépensé.
    public let perishable: Bool

    public init(
        id: String, label: String, unit: MeasureUnit = .g, pieceG: Double? = nil, aisle: Aisle = .autre,
        price: Double? = nil, packs: [Double] = [], perishable: Bool = false
    ) {
        self.id = id
        self.label = label
        self.unit = unit
        self.pieceG = pieceG
        self.aisle = aisle
        self.price = price
        self.packs = packs.filter { $0 > 0 }.sorted()
        self.perishable = perishable
    }

    /// Coût d'une quantité dans l'unité d'achat (€ par kg ou L pour g et ml, € par pièce).
    public func cost(of quantity: Double) -> Double? {
        price.map { unit == .piece ? $0 * quantity : $0 * quantity / 1000 }
    }
}

/// Aliment rattaché à son produit : `edibleYield` g mangés par g acheté (peau, cuisson).
public struct PurchaseLink: Sendable, Equatable {
    public let product: PurchaseProduct
    public let edibleYield: Double
}

/// Prix France (médiane des relevés Open Prices, licence ODbL) par code Ciqual, générés par
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
    let productsById: [String: PurchaseProduct]

    public init(
        prices: [Int: FoodPrice], groupRanges: [Int: ClosedRange<Double>] = [:], links: [Int: PurchaseLink] = [:]
    ) {
        self.prices = prices
        self.groupRanges = groupRanges
        self.links = links
        var byName: [String: PurchaseProduct] = [:]
        var byId: [String: PurchaseProduct] = [:]
        for product in links.values.map(\.product) {
            byName[TextNormalizer.singular(product.label)] = product
            byName[TextNormalizer.singular(product.id)] = product
            byId[product.id] = product
        }
        productsByName = byName
        productsById = byId
    }

    /// Produit par identifiant (clé d'une ligne de courses).
    public func product(id: String) -> PurchaseProduct? { productsById[id] }

    public var allProducts: [PurchaseProduct] { Array(productsById.values) }

    /// Aliment Ciqual « tel qu'acheté » d'un produit (part mangée ≤ 1 la plus haute : cru, égoutté), pour
    /// exprimer un reste en quantité mangeable.
    public func purchasedFood(productId: String) -> (code: Int, edibleYield: Double)? {
        links.filter { $0.value.product.id == productId && $0.value.edibleYield <= 1 }
            .max { ($0.value.edibleYield, -$0.key) < ($1.value.edibleYield, -$1.key) }
            .map { ($0.key, $0.value.edibleYield) }
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

    /// Ligne `products` (libellé, unité d'achat, poids d'une pièce, rayon, prix, paquets, périssable) ;
    /// `nil` si invalide.
    private static func product(id: String, row: [JSONCell]) -> PurchaseProduct? {
        guard row.count >= 4, let label = row[0].text, let unit = row[1].text.flatMap(MeasureUnit.init(rawValue:)) else {
            return nil
        }
        let pieceG = row[2].number.flatMap { $0 > 0 ? $0 : nil }
        guard unit != .piece || pieceG != nil else { return nil }
        let aisle = row[3].text.flatMap(Aisle.init(rawValue:)) ?? .autre
        let cell = { (index: Int) in row.indices.contains(index) ? row[index] : JSONCell.null }
        return PurchaseProduct(
            id: id, label: label, unit: unit, pieceG: pieceG, aisle: aisle, price: cell(4).number,
            packs: cell(5).numbers, perishable: (cell(6).number ?? 0) > 0
        )
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
    case number(Double), text(String), list([Double]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let list = try? container.decode([Double].self) {
            self = .list(list)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    var number: Double? { if case let .number(value) = self { value } else { nil } }
    var text: String? { if case let .text(value) = self { value } else { nil } }
    var numbers: [Double] { if case let .list(value) = self { value } else { [] } }
}
