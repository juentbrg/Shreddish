import Foundation

/// Correspondances nom d'ingrédient → code Ciqual mémorisées sur l'appareil (spec 010).
public protocol FoodMatchCache: Sendable {
    /// `.some(nil)` : connu comme absent de Ciqual.
    func code(for key: String) -> Int??
    func store(_ code: Int?, for key: String)
}

/// Cache en mémoire : tests.
public final class InMemoryFoodMatchCache: FoodMatchCache, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: Int?] = [:]

    public init(_ entries: [String: Int?] = [:]) {
        self.entries = entries
    }

    public func code(for key: String) -> Int?? { lock.withLock { entries[key] } }
    public func store(_ code: Int?, for key: String) { lock.withLock { entries[key] = code } }
}

/// Ingrédient ambigu soumis à l'IA avec ses candidats Ciqual.
public struct FoodQuestion: Codable, Sendable, Equatable {
    public struct Candidate: Codable, Sendable, Equatable {
        public var code: Int
        public var name: String
    }

    /// Position dans la liste envoyée, renvoyée par l'IA avec son choix.
    public var index: Int
    public var name: String
    public var candidates: [Candidate]
}

/// Macros des repas calculées depuis Ciqual (spec 010), prix depuis la table de prix (spec 011).
public struct NutritionResolver: Sendable {
    public let catalog: FoodCatalog
    public let prices: PriceCatalog
    public let cache: any FoodMatchCache
    /// Compléments possédés : macros saisies par l'utilisateur, jamais Ciqual.
    public let supplements: [OwnedSupplement]

    public init(
        catalog: FoodCatalog = .shared, prices: PriceCatalog = .shared, cache: any FoodMatchCache,
        supplements: [OwnedSupplement] = []
    ) {
        self.catalog = catalog
        self.prices = prices
        self.cache = cache
        self.supplements = supplements
    }

    public static func key(_ name: String) -> String { TextNormalizer.singular(name) }

    /// Ingrédients ambigus encore inconnus du cache ; les rapprochements sûrs y sont enregistrés.
    public func questions(for meals: [MealDTO]) -> [FoodQuestion] {
        var asked: Set<String> = []
        var questions: [FoodQuestion] = []
        for ingredient in meals.flatMap(\.ingredients) where supplement(for: ingredient.name) == nil {
            let key = Self.key(ingredient.name)
            guard cache.code(for: key) == nil, !asked.contains(key) else { continue }
            asked.insert(key)
            switch FoodMatcher.match(ingredient.name, in: catalog) {
            case let .confident(food): cache.store(food.code, for: key)
            case .notFound: cache.store(nil, for: key)
            case let .ambiguous(foods):
                questions.append(FoodQuestion(
                    index: questions.count, name: ingredient.name, candidates: foods.map { .init(code: $0.code, name: $0.name) }
                ))
            }
        }
        return questions
    }

    /// Enregistre les choix de l'IA, repérés par position (code hors candidats ignoré) ; question sans
    /// réponse : laissée au meilleur candidat, sans mémorisation.
    public func record(_ choices: [FoodChoice], for questions: [FoodQuestion]) {
        let answers = Dictionary(choices.map { ($0.index, $0.code) }, uniquingKeysWith: { first, _ in first })
        for question in questions {
            guard let answer = answers[question.index] else { continue }
            let allowed = Set(question.candidates.map(\.code))
            cache.store(answer.flatMap { allowed.contains($0) ? $0 : nil }, for: Self.key(question.name))
        }
    }

    /// Repas avec codes Ciqual, macros et prix recalculés. Repas incomplet (ingrédient non trouvé ou pièce
    /// sans poids) : macros de l'IA conservées, renvoyé dans `unverified` ; prix recalculés quand même.
    public func resolve(_ meal: MealDTO) -> (meal: MealDTO, verified: Bool) {
        var meal = meal
        var total = MacroTotals.zero
        var verified = true
        meal.ingredients = meal.ingredients.map { ingredient in
            var ingredient = ingredient
            if let supplement = supplement(for: ingredient.name) {
                if let macros = supplement.macros(grams: ingredient.grams) { total += macros } else { verified = false }
                return ingredient
            }
            let key = Self.key(ingredient.name)
            // Hors cache : rapprochement sûr, ou meilleur candidat si l'IA n'a pas tranché.
            let code = cache.code(for: key) ?? {
                switch FoodMatcher.match(ingredient.name, in: catalog) {
                case let .confident(food): food.code
                case let .ambiguous(foods): foods.first?.code
                case .notFound: nil
                }
            }()
            ingredient.foodCode = code
            ingredient = priced(ingredient)
            guard let code, let food = catalog.food(code: code), let grams = ingredient.grams else {
                verified = false
                return ingredient
            }
            total += food.macros(grams: grams)
            return ingredient
        }
        if verified { meal.macros = total.rounded }
        meal.costEur = BudgetMath.cents(meal.ingredients.reduce(0) { $0 + $1.costEur })
        return (meal, verified)
    }

    /// Ingrédient au prix de la table (ou au prix de l'IA borné), coût recalculé ; complément possédé inchangé.
    public func priced(_ ingredient: IngredientDTO) -> IngredientDTO {
        guard supplement(for: ingredient.name) == nil else { return ingredient }
        var ingredient = ingredient
        let group = ingredient.foodCode.flatMap { catalog.food(code: $0)?.group }
        guard let price = prices.unitPrice(for: ingredient, group: group) else { return ingredient }
        ingredient.unitPriceEur = price
        AIOutputValidator.applyUnitPrice(&ingredient)
        return ingredient
    }

    func supplement(for name: String) -> OwnedSupplement? {
        let haystack = Self.key(name)
        return supplements.first { supplement in
            let needle = Self.key(supplement.name)
            return !needle.isEmpty && haystack.contains(needle)
        }
    }

    /// Macros par g d'un ingrédient rapproché (complément compris) ; `nil` si inconnu.
    public func macrosPerGram(of ingredient: IngredientDTO) -> MacroTotals? {
        if let supplement = supplement(for: ingredient.name) { return supplement.macros(grams: 1) }
        guard let code = ingredient.foodCode, let food = catalog.food(code: code) else { return nil }
        return food.macros(grams: 1)
    }
}

extension OwnedSupplement {
    /// Macros pour `grams` g d'après la dose saisie ; `nil` sans valeurs saisies.
    func macros(grams: Double?) -> MacroTotals? {
        guard kind == .macro, let grams, let serving = servingG, serving > 0, let protein = proteinGPerServing else { return nil }
        let factor = grams / serving
        let carbs = carbsGPerServing ?? 0
        let fat = fatGPerServing ?? 0
        let kcal = kcalPerServing ?? (4 * protein + 4 * carbs + 9 * fat)
        return MacroTotals(kcal: kcal * factor, proteinG: protein * factor, carbsG: carbs * factor, fatG: fat * factor)
    }
}
