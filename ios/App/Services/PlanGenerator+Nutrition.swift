import Foundation
import ShreddishCore

/// Spec 010 : macros Ciqual, portions ajustées, régénération ciblée des jours hors cible.
extension PlanGenerator {
    /// Rapprochement Ciqual, macros recalculées et portions ajustées jour par jour.
    func finish(_ days: [DayPlanDTO], ctx: Context) async -> (days: [DayPlanDTO], unverified: Int) {
        await answerFoodQuestions(for: days.flatMap(\.meals), ctx: ctx)
        var unverified = 0
        let finished = days.map { day in
            let meals = day.meals.map { meal in
                let (resolved, verified) = ctx.resolver.resolve(meal)
                if !verified { unverified += 1 }
                return resolved
            }
            return DayPlanDTO(
                dayOffset: day.dayOffset,
                meals: PortionAdjuster.adjust(meals, to: ctx.targets.macros, resolver: ctx.resolver, oil: ctx.oil)
            )
        }
        return (finished, unverified)
    }

    /// Un seul appel groupé pour les ingrédients ambigus ; en cas d'échec, macros de l'IA conservées.
    func answerFoodQuestions(for meals: [MealDTO], ctx: Context) async {
        let questions = ctx.resolver.questions(for: meals)
        guard !questions.isEmpty else { return }
        do {
            let data = try await client.generate(
                kind: .foodMatch, instructions: PromptBuilder.foodMatchInstructions(),
                input: PromptBuilder.foodMatchInput(questions), model: ctx.model, apiKey: ctx.apiKey
            )
            ctx.resolver.record(try AIResponseDecoder.decodeFoodChoices(data), for: questions)
        } catch {
            // Rapprochements ambigus non résolus : ces repas gardent les macros de l'IA.
        }
    }

    /// Jours hors cible après ajustement, ou aux déjeuners et dîners trop répétés : une régénération avec retour
    /// précis, gardée si elle corrige sans dégrader l'autre critère.
    func retryOffTargetDays(_ days: [DayPlanDTO], ctx: Context) async -> [DayPlanDTO] {
        let targets = ctx.targets.macros
        let repeated = VarietyCheck.repeatedDays(days)
        let toRetry = days.filter {
            repeated[$0.dayOffset] != nil || Totals.needsRegeneration(Totals.planned($0.meals), targets: targets)
        }
        guard !toRetry.isEmpty else { return days }
        let dayLimit = ctx.constraints.budgetCeilingEur / 7
        var replacements: [Int: DayPlanDTO] = [:]
        await withTaskGroup(of: DayPlanDTO?.self) { group in
            for day in toRetry {
                let avoid = days.filter { $0.dayOffset != day.dayOffset }.flatMap(\.meals).map(\.name)
                var feedback: [String] = []
                if let signatures = repeated[day.dayOffset] { feedback.append(PromptBuilder.varietyFeedback(signatures)) }
                if Totals.needsRegeneration(Totals.planned(day.meals), targets: targets) {
                    feedback.append(PromptBuilder.offTargetFeedback(totals: Totals.planned(day.meals), targets: targets))
                }
                let correction = feedback.joined(separator: " ")
                group.addTask {
                    guard let result = try? await self.requestDay(
                        ctx, offset: day.dayOffset, avoid: avoid, costLimit: dayLimit, correction: correction
                    ), let draft = result.sanitized else { return nil }
                    return await self.finish([draft], ctx: ctx).days.first
                }
            }
            for await day in group {
                if let day { replacements[day.dayOffset] = day }
            }
        }
        var result = days
        for (offset, candidate) in replacements.sorted(by: { $0.key < $1.key }) {
            guard let index = result.firstIndex(where: { $0.dayOffset == offset }) else { continue }
            var trial = result
            trial[index] = candidate
            let before = Totals.targetDistance(Totals.planned(result[index].meals), targets: targets)
            let after = Totals.targetDistance(Totals.planned(candidate.meals), targets: targets)
            let repeatsBefore = VarietyCheck.repeatedDays(result).count
            let repeatsAfter = VarietyCheck.repeatedDays(trial).count
            let fixesVariety = repeatsAfter < repeatsBefore && after <= before + 0.15
            let fixesTargets = after < before && repeatsAfter <= repeatsBefore
            if fixesVariety || fixesTargets { result = trial }
        }
        return result
    }

    /// Huile de cuisson, sauf si l'huile ou le colza est exclu.
    static func allowedOil(_ constraints: GenerationConstraints) -> IngredientDTO? {
        let probe = MealDTO(
            type: .lunch, name: "", ingredients: [PortionAdjuster.cookingOil], steps: [], prepMinutes: 0, costEur: 0,
            kcal: 0, proteinG: 0, carbsG: 0, fatG: 0, prepSessionRef: nil
        )
        let excluded = AIOutputValidator.excludedFood(in: probe, excluded: constraints.allergies + constraints.excludedFoods)
        return excluded == nil ? PortionAdjuster.cookingOil : nil
    }

    /// Avertissements après recalcul : écarts et budget sur les valeurs finales, plus les repas non vérifiés.
    static func finalWarnings(
        _ warnings: [ValidationIssue], days: [DayPlanDTO], constraints: GenerationConstraints, unverified: Int,
        includeBudget: Bool = true
    ) -> [ValidationIssue] {
        var result = warnings.filter { !$0.isRecomputed && (!includeBudget || !$0.isBudget) }
        result += AIOutputValidator.offTargetWarnings(days: days, targets: constraints.targets)
        if includeBudget {
            result += AIOutputValidator.budgetWarnings(cost: days.flatMap(\.meals).reduce(0) { $0 + $1.costEur }, constraints: constraints)
        }
        if unverified > 0 { result.append(.unverifiedMeals(count: unverified)) }
        return result
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
