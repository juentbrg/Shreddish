import Foundation
import ShreddishCore

/// Spec 018 : budget vérifié sur le coût calculé par l'application (table de prix), plus par l'IA.
extension PlanGenerator {
    /// Période au-dessus du plafond : les jours les plus chers, assez pour combler l'écart, sont régénérés une fois
    /// avec leurs ingrédients les plus chers ; chaque jour est gardé s'il coûte moins sans s'écarter des cibles.
    func retryOverBudgetDays(_ days: [DayPlanDTO], ctx: Context) async -> [DayPlanDTO] {
        let total = Self.cost(of: days)
        let weekCost = Self.weekCost(of: days, ctx: ctx)
        guard ctx.constraints.budgetCeilingEur > 0, !days.isEmpty, weekCost > ctx.constraints.budgetCeilingEur + 0.01,
              total > 0 else { return days }
        // Plafond ramené à la part mangée : les jours se comparent au coût de leurs repas (additif), la semaine au
        // ticket en paquets entiers (spec 013 FR-1305, spec 021 FR-2112).
        let ceiling = ctx.constraints.budgetCeilingEur * total / weekCost
        let dayLimit = ceiling / Double(days.count)
        var excess = total - ceiling
        var toRetry: [DayPlanDTO] = []
        // Jours avec une recette sauvegardée gardés : elle serait perdue.
        let recipeNames = Set(ctx.recipes.map(\.name))
        let candidates = days.filter { !$0.meals.contains { recipeNames.contains($0.name) } }
        for day in candidates.sorted(by: { Self.cost(of: [$0]) > Self.cost(of: [$1]) })
        where excess > 0 && Self.cost(of: [day]) > dayLimit {
            toRetry.append(day)
            excess -= Self.cost(of: [day]) - dayLimit
        }
        var replacements: [Int: DayPlanDTO] = [:]
        await withTaskGroup(of: (Int, DayPlanDTO?).self) { group in
            for day in toRetry {
                let avoid = days.filter { $0.dayOffset != day.dayOffset }.flatMap(\.meals).map(\.name)
                group.addTask { (day.dayOffset, await self.cheaperDay(than: day, limit: dayLimit, avoid: avoid, ctx: ctx)) }
            }
            for await (offset, day) in group {
                if let day { replacements[offset] = day }
            }
        }
        var result = days
        for (offset, candidate) in replacements.sorted(by: { $0.key < $1.key }) {
            guard let index = result.firstIndex(where: { $0.dayOffset == offset }) else { continue }
            var trial = result
            trial[index] = candidate
            if VarietyCheck.repeatedDays(trial).count <= VarietyCheck.repeatedDays(result).count { result = trial }
        }
        return result
    }

    /// Une régénération du jour avec ses ingrédients les plus chers ; `nil` si elle ne coûte pas moins ou
    /// s'écarte plus des cibles.
    func cheaperDay(than day: DayPlanDTO, limit: Double, avoid: [String], ctx: Context) async -> DayPlanDTO? {
        let cost = Self.cost(of: [day])
        let expensive = day.meals.flatMap(\.ingredients).sorted { $0.costEur > $1.costEur }.prefix(3)
        let feedback = PromptBuilder.overBudgetFeedback(costEur: cost, ceilingEur: limit, expensive: Array(expensive))
        guard let result = try? await requestDay(ctx, offset: day.dayOffset, avoid: avoid, costLimit: limit, correction: feedback),
              let draft = result.sanitized, let candidate = await finish([draft], ctx: ctx).days.first else { return nil }
        let targets = ctx.targets.macros
        let before = Totals.targetDistance(Totals.planned(day.meals), targets: targets)
        let after = Totals.targetDistance(Totals.planned(candidate.meals), targets: targets)
        return Self.cost(of: [candidate]) < cost && after <= before + 0.15 ? candidate : nil
    }

    static func cost(of days: [DayPlanDTO]) -> Double {
        days.flatMap(\.meals).reduce(0) { $0 + $1.costEur }
    }

    /// Coût de la semaine comme l'onglet Courses : paquets entiers moins restes qui se gardent, une portion.
    static func weekCost(of days: [DayPlanDTO], ctx: Context) -> Double {
        let owned = ctx.constraints.ownedSupplements
        return ShoppingListBuilder.summary(ShoppingListBuilder.build(from: days, owned: owned, pantry: ctx.pantry)).weekCostEur
    }
}
