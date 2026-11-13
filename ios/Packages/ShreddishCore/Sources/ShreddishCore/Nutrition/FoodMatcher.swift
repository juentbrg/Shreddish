import Foundation

/// Rapprochement d'un nom d'ingrédient libre avec un aliment Ciqual (spec 010).
public enum FoodMatcher {
    public enum Outcome: Sendable, Equatable {
        /// Meilleur candidat, ou candidats proches aux macros semblables.
        case confident(Food)
        /// Candidats aux macros différentes : l'IA choisit.
        case ambiguous([Food])
        case notFound
    }

    /// Écart de score sous lequel deux candidats sont jugés proches.
    static let tieMargin = 0.2
    /// Score minimal d'un candidat retenu.
    static let minimumScore = 0.55
    /// Écart relatif de kcal et protéines sous lequel des candidats proches sont interchangeables.
    static let macroTolerance = 0.15

    public static func match(_ name: String, in catalog: FoodCatalog = .shared, candidates limit: Int = 5) -> Outcome {
        let ranked = rank(name, in: catalog)
        guard let best = ranked.first, best.score >= minimumScore else { return .notFound }
        // Nom identique à un aliment Ciqual : pas d'ambiguïté.
        let query = Set(tokens(name))
        if let exact = ranked.first(where: { Set(tokens($0.food.name)) == query }) { return .confident(exact.food) }
        let close = ranked.prefix { best.score - $0.score <= tieMargin }.map(\.food)
        if close.allSatisfy({ interchangeable($0, best.food) }) { return .confident(best.food) }
        return .ambiguous(Array(ranked.prefix(limit).map(\.food)))
    }

    /// Candidats classés, meilleur d'abord.
    public static func rank(_ name: String, in catalog: FoodCatalog = .shared) -> [(food: Food, score: Double)] {
        let query = tokens(name)
        guard !query.isEmpty else { return [] }
        return catalog.candidatePositions(for: query)
            .map { (food: catalog.foods[$0], score: score(query: query, food: catalog.tokens[$0])) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.food.name.count < $1.food.name.count }
    }

    static func score(query: [String], food: [String]) -> Double {
        let queryWords = Set(query)
        let foodWords = Set(food)
        var score = Double(queryWords.intersection(foodWords).count) / Double(queryWords.count)
        // Mots en trop (hors état cru ou cuit, traité à part) : variante plus spécifique.
        score -= 0.1 * Double(foodWords.subtracting(queryWords).subtracting(raw).subtracting(cooked).subtracting(neutral).count)
        if let first = food.first, first == query.first { score += 0.15 }
        let wantsCooked = !queryWords.isDisjoint(with: cooked)
        if !wantsCooked, !foodWords.isDisjoint(with: cooked) { score -= 0.2 }
        if !wantsCooked, !foodWords.isDisjoint(with: raw) { score += 0.1 }
        return score
    }

    static func interchangeable(_ lhs: Food, _ rhs: Food) -> Bool {
        func close(_ left: Double, _ right: Double, floor: Double) -> Bool {
            abs(left - right) <= max(floor, macroTolerance * max(left, right))
        }
        return close(lhs.per100g.kcal, rhs.per100g.kcal, floor: 15)
            && close(lhs.per100g.proteinG, rhs.per100g.proteinG, floor: 2)
            && close(lhs.per100g.fatG, rhs.per100g.fatG, floor: 2)
    }

    // MARK: Normalisation

    /// Mots normalisés : sans accents, au singulier, synonymes ramenés au vocabulaire Ciqual ;
    /// « 0 % » → « p0 ».
    public static func tokens(_ text: String) -> [String] {
        var text = TextNormalizer.basic(text)
        text = text.replacing(/(\d+(?:[.,]\d+)?)\s*%/) { match in " p\(match.output.1.replacingOccurrences(of: ",", with: ".")) " }
        return text
            .split { !$0.isLetter && !$0.isNumber && $0 != "." }
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .compactMap { word -> String? in
                guard !word.isEmpty, !stopWords.contains(word) else { return nil }
                var word = word
                if word.count > 3, word.hasSuffix("x") { word.removeLast() } else if word.count > 3, word.hasSuffix("s"),
                    !word.hasSuffix("ss") { word.removeLast() }
                return synonyms[word] ?? word
            }
    }

    private static let stopWords: Set<String> = [
        "de", "du", "des", "la", "le", "les", "aux", "au", "a", "en", "et", "avec", "sans", "l", "d", "ou", "pour",
        "type", "mg", "moulu", "moulue", "rape", "rapee", "surgele", "surgelee", "naturel",
    ]
    private static let synonyms: [String: String] = [
        "boite": "appertise", "conserve": "appertise", "appertisee": "appertise",
        "egouttee": "egoutte", "seche": "sec", "crue": "cru", "cuite": "cuit",
    ]
    private static let cooked: Set<String> = [
        "appertise", "cuit", "frit", "frite", "pane", "panee", "grille", "grillee", "roti", "rotie", "braise", "poele",
        "poelee", "bouilli", "bouillie", "sauce", "prepare", "preparee", "reconstitue", "reconstituee", "vapeur",
    ]
    private static let raw: Set<String> = ["cru"]
    /// Descriptions de la forme courante (« chair », « viande et peau ») : pas une variante.
    private static let neutral: Set<String> = [
        "chair", "peau", "viande", "standard", "entier", "entiere", "frai", "fraiche", "sec", "nature",
    ]
}
