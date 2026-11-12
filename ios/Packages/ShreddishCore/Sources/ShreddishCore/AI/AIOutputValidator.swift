import Foundation

/// Contraintes vérifiées localement sur chaque réponse IA (research R6).
public struct GenerationConstraints: Sendable, Equatable {
    public var targets: MacroTotals
    public var mealsPerDay: Int
    public var maxPrepMinutes: Int
    public var dailyBudgetEur: Double
    public var batchCooking: Bool
    public var excludedFoods: [String]

    public init(
        targets: MacroTotals, mealsPerDay: Int, maxPrepMinutes: Int, dailyBudgetEur: Double,
        batchCooking: Bool, excludedFoods: [String]
    ) {
        self.targets = targets
        self.mealsPerDay = mealsPerDay
        self.maxPrepMinutes = maxPrepMinutes
        self.dailyBudgetEur = dailyBudgetEur
        self.batchCooking = batchCooking
        self.excludedFoods = excludedFoods
    }
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
    case prepSessionCount(Int)
    case orphanPrepSessionRef(meal: String, ref: Int)
    // Corrections appliquées.
    case kcalRecomputed(meal: String)
    case unitConverted(ingredient: String)
    case prepSessionRefCleared(meal: String)
    case mealTypeCorrected(meal: String)
    // Avertissements affichés.
    case dayOffTarget(dayOffset: Int, deviation: Double)
    case dayOverBudget(dayOffset: Int, costEur: Double)
}

public struct ValidationResult<Value: Sendable>: Sendable {
    public var fatal: [ValidationIssue] = []
    public var corrected: [ValidationIssue] = []
    public var warnings: [ValidationIssue] = []
    /// Version corrigée ; `nil` si au moins une erreur fatale.
    public var sanitized: Value?

    public init() {}

    public var isValid: Bool { fatal.isEmpty }
}

public enum AIOutputValidator {
    /// Écart kcal annoncées / recalculées toléré avant correction.
    static let kcalTolerance = 0.10
    /// Coût d'un jour toléré au-delà du budget avant signalement.
    static let budgetTolerance = 1.10

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
        let cost = meals.reduce(0) { $0 + $1.costEur }
        if result.fatal.isEmpty, cost > constraints.dailyBudgetEur * budgetTolerance + 0.000_1 {
            result.warnings.append(.dayOverBudget(dayOffset: expectedOffset, costEur: cost))
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

        meal.ingredients = meal.ingredients.map { normalizeUnit($0, result: &result) }

        if let food = excludedFood(in: meal, excluded: constraints.excludedFoods) {
            result.fatal.append(.excludedFood(meal: name, food: food))
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
