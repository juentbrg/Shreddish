import Foundation

/// Aliment Ciqual : valeurs pour 100 g (spec 010).
public struct Food: Sendable, Equatable, Hashable {
    public let code: Int
    public let name: String
    public let group: Int
    public let per100g: MacroTotals

    public init(code: Int, name: String, group: Int, per100g: MacroTotals) {
        self.code = code
        self.name = name
        self.group = group
        self.per100g = per100g
    }

    public func macros(grams: Double) -> MacroTotals {
        let factor = grams / 100
        return MacroTotals(
            kcal: per100g.kcal * factor, proteinG: per100g.proteinG * factor,
            carbsG: per100g.carbsG * factor, fatG: per100g.fatG * factor
        )
    }

    public static func == (lhs: Food, rhs: Food) -> Bool { lhs.code == rhs.code }
    public func hash(into hasher: inout Hasher) { hasher.combine(code) }
}

/// Table Ciqual 2025 (ANSES, Licence Ouverte Etalab 2.0), générée par `tools/ciqual/build_catalog.py`.
public final class FoodCatalog: Sendable {
    public static let attribution = "Valeurs nutritionnelles : table Ciqual 2025, ANSES (Licence Ouverte Etalab 2.0)."

    /// Catalogue embarqué, chargé au premier usage.
    public static let shared: FoodCatalog = {
        guard let url = Bundle.module.url(forResource: "ciqual", withExtension: "json"),
              let data = try? Data(contentsOf: url), let catalog = try? FoodCatalog(json: data) else {
            return FoodCatalog(foods: [])
        }
        return catalog
    }()

    public let foods: [Food]
    let tokens: [[String]]
    private let byCode: [Int: Int]
    /// Mot → aliments qui le contiennent.
    private let index: [String: [Int]]

    public init(foods: [Food]) {
        self.foods = foods
        tokens = foods.map { FoodMatcher.tokens($0.name) }
        byCode = Dictionary(foods.enumerated().map { ($1.code, $0) }, uniquingKeysWith: { first, _ in first })
        var index: [String: [Int]] = [:]
        for (position, words) in tokens.enumerated() {
            for word in Set(words) { index[word, default: []].append(position) }
        }
        self.index = index
    }

    convenience init(json: Data) throws {
        struct File: Decodable { let foods: [[Entry]] }
        enum Entry: Decodable {
            case number(Double)
            case text(String)
            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let number = try? container.decode(Double.self) { self = .number(number) } else {
                    self = .text(try container.decode(String.self))
                }
            }
            var number: Double { if case let .number(value) = self { value } else { 0 } }
            var text: String { if case let .text(value) = self { value } else { "" } }
        }
        let file = try JSONDecoder().decode(File.self, from: json)
        self.init(foods: file.foods.compactMap { row in
            guard row.count >= 7 else { return nil }
            return Food(
                code: Int(row[0].number), name: row[1].text, group: Int(row[2].number),
                per100g: MacroTotals(kcal: row[3].number, proteinG: row[4].number, carbsG: row[5].number, fatG: row[6].number)
            )
        })
    }

    public func food(code: Int) -> Food? {
        byCode[code].map { foods[$0] }
    }

    /// Positions des aliments partageant au moins un mot avec la requête.
    func candidatePositions(for words: [String]) -> Set<Int> {
        Set(words.flatMap { index[$0] ?? [] })
    }
}
