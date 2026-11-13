import Foundation

/// Contraintes vérifiées localement sur chaque réponse IA (research R6).
public struct GenerationConstraints: Sendable, Equatable {
    public var targets: MacroTotals
    public var mealsPerDay: Int
    public var maxPrepMinutes: Int
    public var weeklyBudgetEur: Double
    /// Dépassement toléré du budget hebdo, 0 à 0,20 (spec 003).
    public var budgetTolerance: Double
    public var batchCooking: Bool
    public var allergies: [String]
    /// Aliments que l'utilisateur n'aime pas.
    public var excludedFoods: [String]
    /// Plafond de coût d'un jour régénéré ou d'un repas remplacé (FR-203).
    public var costLimitEur: Double?
    /// Compléments possédés : coût ramené à 0 (spec 004).
    public var ownedSupplements: [String]

    public init(
        targets: MacroTotals, mealsPerDay: Int, maxPrepMinutes: Int, weeklyBudgetEur: Double, budgetTolerance: Double,
        batchCooking: Bool, allergies: [String], excludedFoods: [String], costLimitEur: Double? = nil,
        ownedSupplements: [String] = []
    ) {
        self.targets = targets
        self.mealsPerDay = mealsPerDay
        self.maxPrepMinutes = maxPrepMinutes
        self.weeklyBudgetEur = weeklyBudgetEur
        self.budgetTolerance = budgetTolerance
        self.batchCooking = batchCooking
        self.allergies = allergies
        self.excludedFoods = excludedFoods
        self.costLimitEur = costLimitEur
        self.ownedSupplements = ownedSupplements
    }

    /// Budget × (1 + tolérance).
    public var budgetCeilingEur: Double { weeklyBudgetEur * (1 + budgetTolerance) }
}

/// Plafonds de coût pour une régénération partielle (FR-203).
public enum BudgetMath {
    public static func dayLimit(weeklyBudget: Double, tolerance: Double, otherDaysCost: Double) -> Double {
        max(0, weeklyBudget * (1 + tolerance) - otherDaysCost)
    }

    public static func mealLimit(dayLimit: Double, otherMealsCost: Double) -> Double {
        max(0, dayLimit - otherMealsCost)
    }

    /// Arrondi au centime, pour les messages et les comparaisons.
    public static func cents(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

public enum ValidationIssue: Equatable, Sendable {
    // Fatals : rejet + retry.
    case wrongDays
    case wrongMealCount(dayOffset: Int, count: Int)
    case incompleteMeal(meal: String)
    case invalidQuantity(ingredient: String)
    case invalidUnit(ingredient: String, unit: String)
    case negativeValue(meal: String)
    case prepTooLong(meal: String, minutes: Int)
    case excludedFood(meal: String, food: String)
    case allergen(meal: String, food: String)
    case prepSessionCount(Int)
    case orphanPrepSessionRef(meal: String, ref: Int)
    // Corrections appliquées.
    case kcalRecomputed(meal: String)
    case unitConverted(ingredient: String)
    case prepSessionRefCleared(meal: String)
    case mealTypeCorrected(meal: String)
    case supplementCostCleared(meal: String)
    case invalidTimeCleared(meal: String)
    // Avertissements affichés. Budget : nouvel essai avec retour de coût, puis accepté (spec 004).
    case dayOffTarget(dayOffset: Int, deviation: Double)
    case weekOverBudgetWithinTolerance(costEur: Double, budgetEur: Double)
    case weekOverBudget(costEur: Double, ceilingEur: Double)
    case overCostLimit(costEur: Double, limitEur: Double)

    /// Coût au-dessus du plafond : justifie un nouvel essai avec retour de coût.
    public var isOverCeiling: Bool {
        switch self {
        case .weekOverBudget, .overCostLimit: true
        default: false
        }
    }
}

public struct ValidationResult<Value: Sendable>: Sendable {
    public var fatal: [ValidationIssue] = []
    public var corrected: [ValidationIssue] = []
    public var warnings: [ValidationIssue] = []
    /// Version corrigée ; `nil` si au moins une erreur fatale.
    public var sanitized: Value?

    public init() {}

    public var isValid: Bool { fatal.isEmpty }

    /// Premier dépassement de plafond (coût, plafond), le plus global en dernier.
    public var overCeiling: (costEur: Double, limitEur: Double)? {
        for issue in warnings.reversed() {
            switch issue {
            case let .weekOverBudget(cost, ceiling): return (cost, ceiling)
            case let .overCostLimit(cost, limit): return (cost, limit)
            default: continue
            }
        }
        return nil
    }
}

public enum AIOutputValidator {
    /// Écart kcal annoncées / recalculées toléré avant correction.
    static let kcalTolerance = 0.10
    /// Marge d'arrondi sur les coûts, en euros.
    static let costEpsilon = 0.005

    // MARK: Semaine

    public static func validate(week: WeekPlanDTO, constraints: GenerationConstraints) -> ValidationResult<WeekPlanDTO> {
        var result = ValidationResult<WeekPlanDTO>()
        let offsets = week.days.map(\.dayOffset).sorted()
        if offsets != Array(0...6) {
            result.fatal.append(.wrongDays)
        }

        let sessionIndexes = Set(week.prepSessions.map(\.index))
        var sessions = week.prepSessions
        if constraints.batchCooking {
            if !(1...2).contains(sessions.count) {
                result.fatal.append(.prepSessionCount(sessions.count))
            }
        } else {
            sessions = []
        }

        var days: [DayPlanDTO] = []
        for day in week.days.sorted(by: { $0.dayOffset < $1.dayOffset }) {
            let dayResult = validate(
                day: day, constraints: constraints, expectedOffset: day.dayOffset,
                prepSessionIndexes: sessionIndexes, strictPrepRefs: constraints.batchCooking
            )
            merge(dayResult, into: &result)
            if let sanitized = dayResult.sanitized { days.append(sanitized) }
        }

        if result.fatal.isEmpty {
            let cost = BudgetMath.cents(days.flatMap(\.meals).reduce(0) { $0 + $1.costEur })
            if cost > constraints.budgetCeilingEur + costEpsilon {
                result.warnings.append(.weekOverBudget(costEur: cost, ceilingEur: BudgetMath.cents(constraints.budgetCeilingEur)))
            } else if cost > constraints.weeklyBudgetEur + costEpsilon {
                result.warnings.append(.weekOverBudgetWithinTolerance(costEur: cost, budgetEur: constraints.weeklyBudgetEur))
            }
        }
        result.sanitized = result.fatal.isEmpty ? WeekPlanDTO(prepSessions: sessions, days: days) : nil
        return result
    }

    // MARK: Jour

    /// Valide un jour. `prepSessionIndexes` : sessions de préparation existantes du planning ;
    /// `strictPrepRefs` : référence inconnue fatale (semaine en batch) ou effacée (régénération).
    public static func validate(
        day: DayPlanDTO, constraints: GenerationConstraints, expectedOffset: Int,
        prepSessionIndexes: Set<Int> = [], strictPrepRefs: Bool = false
    ) -> ValidationResult<DayPlanDTO> {
        var result = ValidationResult<DayPlanDTO>()
        if day.meals.count != constraints.mealsPerDay {
            result.fatal.append(.wrongMealCount(dayOffset: expectedOffset, count: day.meals.count))
        }

        var meals: [MealDTO] = []
        for meal in day.meals {
            var mealResult = validate(meal: meal, constraints: constraints)
            if var sanitized = mealResult.sanitized, let ref = sanitized.prepSessionRef {
                if !constraints.batchCooking || !prepSessionIndexes.contains(ref) {
                    if constraints.batchCooking && strictPrepRefs {
                        mealResult.fatal.append(.orphanPrepSessionRef(meal: sanitized.name, ref: ref))
                    } else {
                        sanitized.prepSessionRef = nil
                        mealResult.corrected.append(.prepSessionRefCleared(meal: sanitized.name))
                    }
                    mealResult.sanitized = sanitized
                }
            }
            merge(mealResult, into: &result)
            if mealResult.fatal.isEmpty, let sanitized = mealResult.sanitized { meals.append(sanitized) }
        }

        let total = Totals.planned(meals)
        let deviation = Totals.deviation(total, targetKcal: constraints.targets.kcal)
        if result.fatal.isEmpty, Totals.isOffTarget(deviation) {
            result.warnings.append(.dayOffTarget(dayOffset: expectedOffset, deviation: deviation))
        }
        let cost = BudgetMath.cents(meals.reduce(0) { $0 + $1.costEur })
        if result.fatal.isEmpty, let limit = constraints.costLimitEur, cost > limit + costEpsilon {
            result.warnings.append(.overCostLimit(costEur: cost, limitEur: BudgetMath.cents(limit)))
        }

        result.sanitized = result.fatal.isEmpty ? DayPlanDTO(dayOffset: expectedOffset, meals: meals) : nil
        return result
    }

    // MARK: Repas

    public static func validate(
        meal: MealDTO, constraints: GenerationConstraints, expectedType: MealType? = nil
    ) -> ValidationResult<MealDTO> {
        var result = ValidationResult<MealDTO>()
        var meal = meal
        let name = meal.name.trimmingCharacters(in: .whitespacesAndNewlines)

        if name.isEmpty || meal.ingredients.isEmpty || meal.steps.isEmpty {
            result.fatal.append(.incompleteMeal(meal: meal.name))
        }
        if let expectedType, meal.type != expectedType {
            meal.type = expectedType
            result.corrected.append(.mealTypeCorrected(meal: name))
        }
        if [meal.kcal, meal.proteinG, meal.carbsG, meal.fatG, meal.costEur].contains(where: { $0 < 0 })
            || meal.prepMinutes < 0 {
            result.fatal.append(.negativeValue(meal: name))
        }
        if meal.prepMinutes > constraints.maxPrepMinutes {
            result.fatal.append(.prepTooLong(meal: name, minutes: meal.prepMinutes))
        }

        meal.ingredients = meal.ingredients.map { ingredient in
            var ingredient = normalizeUnit(ingredient, result: &result)
            ingredient.aisle = AisleClassifier.corrected(name: ingredient.name, aisle: ingredient.aisle)
            return ingredient
        }
        applyUnitPrices(&meal)

        if let food = excludedFood(in: meal, excluded: constraints.allergies) {
            result.fatal.append(.allergen(meal: name, food: food))
        }
        if let food = excludedFood(in: meal, excluded: constraints.excludedFoods) {
            result.fatal.append(.excludedFood(meal: name, food: food))
        }
        clearSupplementCosts(&meal, owned: constraints.ownedSupplements, name: name, result: &result)
        if let time = meal.time, !isValidTime(time) {
            meal.time = nil
            result.corrected.append(.invalidTimeCleared(meal: name))
        }

        let computed = meal.macros.kcalFromMacros
        if computed > 0, abs(meal.kcal - computed) / computed > kcalTolerance {
            meal.kcal = computed
            result.corrected.append(.kcalRecomputed(meal: name))
        }

        meal.name = name
        result.sanitized = result.fatal.isEmpty ? meal : nil
        return result
    }

    // MARK: Helpers

    /// Coût déterministe (spec 005) : quantité × prix unitaire, puis coût du repas = somme des ingrédients.
    static func applyUnitPrices(_ meal: inout MealDTO) {
        guard !meal.ingredients.isEmpty else { return }
        meal.ingredients = meal.ingredients.map { ingredient in
            guard let price = ingredient.unitPriceEur, price >= 0, let unit = ingredient.measureUnit else { return ingredient }
            var ingredient = ingredient
            let divisor: Double = unit == .piece ? 1 : 1000
            ingredient.costEur = BudgetMath.cents(ingredient.quantity * price / divisor)
            return ingredient
        }
        if meal.ingredients.contains(where: { $0.unitPriceEur != nil }) {
            meal.costEur = BudgetMath.cents(meal.ingredients.reduce(0) { $0 + $1.costEur })
        }
    }

    /// Ingrédients issus d'un complément possédé : coût 0, retiré du coût du repas (FR-303).
    private static func clearSupplementCosts<T>(
        _ meal: inout MealDTO, owned: [String], name: String, result: inout ValidationResult<T>
    ) {
        var removed = 0.0
        meal.ingredients = meal.ingredients.map { ingredient in
            guard ingredient.costEur > 0, isOwnedSupplement(ingredient.name, owned: owned) else { return ingredient }
            var ingredient = ingredient
            removed += ingredient.costEur
            ingredient.costEur = 0
            return ingredient
        }
        if removed > 0 {
            meal.costEur = max(0, meal.costEur - removed)
            result.corrected.append(.supplementCostCleared(meal: name))
        }
    }

    public static func isOwnedSupplement(_ ingredient: String, owned: [String]) -> Bool {
        let haystack = TextNormalizer.singular(ingredient)
        return owned.contains { item in
            let needle = TextNormalizer.singular(item)
            return !needle.isEmpty && haystack.contains(needle)
        }
    }

    /// « HH:mm » 00:00 à 23:59 (« 7:30 » accepté).
    static func isValidTime(_ text: String) -> Bool {
        let parts = text.split(separator: ":")
        guard parts.count == 2, parts[1].count == 2, (1...2).contains(parts[0].count),
              let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return false }
        return (0...23).contains(hours) && (0...59).contains(minutes)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func normalizeUnit<T>(_ ingredient: IngredientDTO, result: inout ValidationResult<T>) -> IngredientDTO {
        var ingredient = ingredient
        guard ingredient.quantity > 0, ingredient.costEur >= 0 else {
            result.fatal.append(.invalidQuantity(ingredient: ingredient.name))
            return ingredient
        }
        let raw = TextNormalizer.basic(ingredient.unit).replacingOccurrences(of: ".", with: "")
        let conversion: (MeasureUnit, Double)? = switch raw {
        case "g", "gr", "gramme", "grammes": (.g, 1)
        case "kg", "kilo", "kilos", "kilogramme", "kilogrammes": (.g, 1000)
        case "ml", "millilitre", "millilitres": (.ml, 1)
        case "cl", "centilitre", "centilitres": (.ml, 10)
        case "l", "litre", "litres": (.ml, 1000)
        case "piece", "pieces", "pc", "pcs", "unite", "unites": (.piece, 1)
        default: nil
        }
        guard let (unit, factor) = conversion else {
            result.fatal.append(.invalidUnit(ingredient: ingredient.name, unit: ingredient.unit))
            return ingredient
        }
        if factor != 1 || ingredient.unit != unit.rawValue {
            if factor != 1 { result.corrected.append(.unitConverted(ingredient: ingredient.name)) }
            ingredient.quantity *= factor
            ingredient.unit = unit.rawValue
        }
        return ingredient
    }

    /// Premier aliment exclu présent dans le nom du repas ou d'un ingrédient (forme d'origine).
    static func excludedFood(in meal: MealDTO, excluded: [String]) -> String? {
        let haystacks = ([meal.name] + meal.ingredients.map(\.name)).map(TextNormalizer.singular)
        return excluded.first { food in
            let needle = TextNormalizer.singular(food)
            return !needle.isEmpty && haystacks.contains { $0.contains(needle) }
        }
    }

    private static func merge<A, B>(_ source: ValidationResult<A>, into target: inout ValidationResult<B>) {
        target.fatal.append(contentsOf: source.fatal)
        target.corrected.append(contentsOf: source.corrected)
        target.warnings.append(contentsOf: source.warnings)
    }
}
