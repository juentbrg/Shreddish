import Foundation

/// Ajuste les portions d'un jour (ou d'un repas) pour atteindre les cibles, avec les macros Ciqual (spec 010).
/// Trois leviers : sources de protéines, féculents, matières grasses, chacun multiplié par un facteur borné.
/// Légumes, pièces et compléments ne bougent pas.
public enum PortionAdjuster {
    public static let factorRange = 0.6...1.6
    /// Matières grasses (huile, beurre, oléagineux) : petites quantités, marge plus large.
    public static let fatFactorRange = 0.5...3.0
    /// Sous ces kcal pour 100 g, un aliment est un légume ou un condiment : quantité fixe.
    static let lowEnergyKcal = 60.0

    enum Lever: Int, CaseIterable {
        case protein, carbs, fat
    }

    /// Huile de cuisson ajoutée quand aucun ingrédient ne permet d'atteindre les lipides (Ciqual 17130, colza).
    public static let cookingOil = IngredientDTO(
        name: "Huile de colza", quantity: 0, unit: "ml", aisle: .epicerie, costEur: 0, unitPriceEur: 3.5, foodCode: 17130
    )
    static let maxOilPerMealMl = 20.0
    /// Manque de lipides toléré avant ajout d'huile, en g.
    static let fatGapTolerance = 5.0

    /// Repas ajustés. `targets` : cibles du jour, ou macros restantes pour un repas remplacé. `oil` : huile
    /// ajoutée aux déjeuners et dîners si les lipides restent trop bas ; `nil` si l'huile est exclue.
    public static func adjust(
        _ meals: [MealDTO], to targets: MacroTotals, resolver: NutritionResolver, oil: IngredientDTO? = cookingOil
    ) -> [MealDTO] {
        let scaled = scale(meals, to: targets, resolver: resolver)
        guard let oil else { return scaled }
        return topUpFat(scaled, to: targets, oil: oil, resolver: resolver)
    }

    static func scale(_ meals: [MealDTO], to targets: MacroTotals, resolver: NutritionResolver) -> [MealDTO] {
        var fixed = MacroTotals.zero
        var levers = Array(repeating: MacroTotals.zero, count: Lever.allCases.count)
        for meal in meals {
            guard let parts = parts(of: meal, resolver: resolver) else {
                fixed += meal.macros
                continue
            }
            for part in parts {
                if let lever = part.lever { levers[lever.rawValue] += part.macros } else {
                    fixed += part.macros
                }
            }
        }
        let factors = solve(fixed: fixed, levers: levers, targets: targets)
        guard factors.contains(where: { abs($0 - 1) > 0.02 }) else { return meals }
        return meals.map { meal in apply(factors, to: meal, resolver: resolver) }
    }

    /// Lipides encore trop bas : huile répartie sur les déjeuners et dîners (sinon tous les repas cuisinés).
    static func topUpFat(_ meals: [MealDTO], to targets: MacroTotals, oil: IngredientDTO, resolver: NutritionResolver) -> [MealDTO] {
        let gap = targets.fatG - Totals.planned(meals).fatG
        guard gap > fatGapTolerance, let perMl = resolver.macrosPerGram(of: oil), perMl.fatG > 0 else { return meals }
        var hosts = meals.indices.filter { [.lunch, .dinner].contains(meals[$0].type) }
        if hosts.isEmpty { hosts = meals.indices.filter { meals[$0].type != .snack } }
        guard !hosts.isEmpty else { return meals }
        let share = min(maxOilPerMealMl, gap / perMl.fatG / Double(hosts.count))
        let quantity = max(5, (share / 5).rounded() * 5)
        var result = meals
        for index in hosts {
            var meal = result[index]
            if let existing = meal.ingredients.firstIndex(where: { NutritionResolver.key($0.name).hasPrefix("huile") }) {
                meal.ingredients[existing].quantity += quantity
                AIOutputValidator.applyUnitPrice(&meal.ingredients[existing])
            } else {
                var line = oil
                line.quantity = quantity
                meal.ingredients.append(resolver.priced(line))
            }
            let added = perMl * quantity
            meal.macros = (meal.macros + added).rounded
            meal.costEur = BudgetMath.cents(meal.ingredients.reduce(0) { $0 + $1.costEur })
            result[index] = meal
        }
        return result
    }

    // MARK: Calcul

    struct Part {
        var macros: MacroTotals
        var lever: Lever?
    }

    /// Macros de chaque ingrédient et levier associé ; `nil` si le repas n'est pas entièrement rapproché.
    static func parts(of meal: MealDTO, resolver: NutritionResolver) -> [Part]? {
        var parts: [Part] = []
        for ingredient in meal.ingredients {
            guard let perGram = resolver.macrosPerGram(of: ingredient), let grams = ingredient.grams else { return nil }
            let macros = perGram * grams
            let adjustable = ingredient.measureUnit != .piece && resolver.supplement(for: ingredient.name) == nil
            parts.append(Part(macros: macros, lever: adjustable ? lever(perGram) : nil))
        }
        return parts
    }

    /// Levier dominant d'après la part d'énergie ; `nil` pour un aliment peu énergétique.
    static func lever(_ perGram: MacroTotals) -> Lever? {
        let kcal = perGram.kcal * 100
        guard kcal >= lowEnergyKcal else { return nil }
        let protein = 4 * perGram.proteinG * 100 / kcal
        let carbs = 4 * perGram.carbsG * 100 / kcal
        let fat = 9 * perGram.fatG * 100 / kcal
        if protein >= 0.4 { return .protein }
        return carbs >= fat ? .carbs : .fat
    }

    /// Facteurs bornés minimisant l'écart relatif sur protéines (prioritaires), kcal, glucides et lipides.
    static func solve(fixed: MacroTotals, levers: [MacroTotals], targets: MacroTotals) -> [Double] {
        let goals = [targets.proteinG, targets.carbsG, targets.fatG, targets.kcal]
        let weights = [3.0, 1.0, 1.0, 2.0]
        func vector(_ macros: MacroTotals) -> [Double] { [macros.proteinG, macros.carbsG, macros.fatG, macros.kcal] }
        let base = vector(fixed)
        let columns = levers.map(vector)
        var factors = Array(repeating: 1.0, count: levers.count)
        for _ in 0..<60 {
            for lever in factors.indices {
                var numerator = 0.0
                var denominator = 0.0
                for index in goals.indices where goals[index] > 0 {
                    let others = base[index] + factors.indices.filter { $0 != lever }
                        .reduce(0) { $0 + factors[$1] * columns[$1][index] }
                    let scale = weights[index] / (goals[index] * goals[index])
                    numerator += scale * (goals[index] - others) * columns[lever][index]
                    denominator += scale * columns[lever][index] * columns[lever][index]
                }
                guard denominator > 0 else { continue }
                let range = lever == Lever.fat.rawValue ? fatFactorRange : factorRange
                factors[lever] = min(max(numerator / denominator, range.lowerBound), range.upperBound)
            }
        }
        return factors
    }

    static func apply(_ factors: [Double], to meal: MealDTO, resolver: NutritionResolver) -> MealDTO {
        guard parts(of: meal, resolver: resolver) != nil else { return meal }
        var meal = meal
        var total = MacroTotals.zero
        meal.ingredients = meal.ingredients.map { ingredient in
            var ingredient = ingredient
            guard let perGram = resolver.macrosPerGram(of: ingredient) else { return ingredient }
            let adjustable = ingredient.measureUnit != .piece && resolver.supplement(for: ingredient.name) == nil
            if adjustable, let lever = lever(perGram) {
                ingredient.quantity = roundedQuantity(ingredient.quantity * factors[lever.rawValue])
                AIOutputValidator.applyUnitPrice(&ingredient)
            }
            total += perGram * (ingredient.grams ?? 0)
            return ingredient
        }
        meal.macros = total.rounded
        meal.costEur = BudgetMath.cents(meal.ingredients.reduce(0) { $0 + $1.costEur })
        return meal
    }

    /// Au gramme sous 20 g, aux 5 g au-delà.
    static func roundedQuantity(_ quantity: Double) -> Double {
        quantity < 20 ? max(1, quantity.rounded()) : (quantity / 5).rounded() * 5
    }
}

extension MacroTotals {
    static func * (lhs: MacroTotals, rhs: Double) -> MacroTotals {
        MacroTotals(kcal: lhs.kcal * rhs, proteinG: lhs.proteinG * rhs, carbsG: lhs.carbsG * rhs, fatG: lhs.fatG * rhs)
    }
}
