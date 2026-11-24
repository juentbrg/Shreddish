import Foundation
import ShreddishCore
import SwiftData

/// Orchestration de la génération : prompt → appel → validation → retry → sauvegarde (research R5, R6).
/// Déclenché seulement par une action de l'utilisateur, jamais en tâche de fond (FR-020).
@MainActor
final class PlanGenerator {
    let client: OpenAIClient
    private let keyStore: any APIKeyStore
    private let clock: any AppClock
    /// Correspondances ingrédient → Ciqual (spec 010).
    let matchCache: any FoodMatchCache

    init(
        client: OpenAIClient, keyStore: any APIKeyStore, clock: any AppClock,
        matchCache: any FoodMatchCache = InMemoryFoodMatchCache()
    ) {
        self.client = client
        self.keyStore = keyStore
        self.clock = clock
        self.matchCache = matchCache
    }

    struct Context: Sendable {
        let apiKey: String
        let targets: NutritionTargets
        let goal: Goal
        var preferences: PromptPreferences
        var constraints: GenerationConstraints
        let model: String
        let resolver: NutritionResolver
        /// Huile ajoutée si les lipides manquent ; `nil` si exclue (allergie ou aliment non aimé).
        let oil: IngredientDTO?
        /// Ingrédients à écouler (spec 013), rapprochés de Ciqual.
        var pantry: [IngredientDTO] = []
        /// Recettes sauvegardées à replacer (spec 014).
        var recipes: [MealDTO] = []
        /// Texte de la semaine reçu en flux (spec 017, FR-1717).
        var onText: (@Sendable (String) -> Void)?
    }

    /// `portions` : foyer (spec 017) ; l'IA prévoit une portion, avec la part du budget correspondante.
    private func context(profile: Profile, preferences: Preferences, portions: Double) throws(AIError) -> Context {
        guard let key = keyStore.read() else { throw .missingKey }
        guard let targets = profile.targets(clock: clock) else { throw .unexpected("Profil invalide") }
        let model = preferences.aiModel.trimmingCharacters(in: .whitespaces)
        var promptPreferences = preferences.promptPreferences
        promptPreferences.trainingSessionsPerWeek = profile.training?.sessionsPerWeek
        promptPreferences.weeklyBudgetEur /= portions
        promptPreferences.language = Self.outputLanguage
        var constraints = preferences.constraints(targets: targets.macros)
        constraints.weeklyBudgetEur /= portions
        return Context(
            apiKey: key, targets: targets, goal: profile.goal, preferences: promptPreferences,
            constraints: constraints,
            model: model.isEmpty ? AIConfig.defaultModel : model,
            resolver: NutritionResolver(cache: matchCache, supplements: preferences.ownedSupplementDetails),
            oil: Self.allowedOil(preferences.constraints(targets: targets.macros))
        )
    }

    /// Langue de l'appareil pour les plats et recettes ; nil en français (spec 017, FR-1712).
    static var outputLanguage: String? {
        let code = Locale.current.language.languageCode?.identifier ?? "fr"
        return code == "fr" ? nil : code
    }

    /// Budget d'une portion : budget du foyer ÷ portions.
    static func perPortion(_ constraints: GenerationConstraints, _ portions: Double) -> GenerationConstraints {
        var constraints = constraints
        constraints.weeklyBudgetEur /= portions
        return constraints
    }

    // MARK: Semaine

    /// Génère et enregistre `dayCount` jours (1 à 7) à partir de `startDay` (aujourd'hui par défaut, ou plus tard : spec 006).
    /// Budget hebdo ramené à la période. Renvoie les avertissements (jours hors cible, période au-dessus du budget).
    @discardableResult
    func generateWeek(
        profile: Profile, preferences: Preferences, startDay: LocalDay? = nil, dayCount: Int = 7, pantry: [IngredientDTO] = [],
        recipes: [MealDTO] = [], in store: ModelContext, onText: (@Sendable (String) -> Void)? = nil
    ) async throws(AIError) -> [ValidationIssue] {
        let startDay = max(startDay ?? clock.today, clock.today)
        if let kcal = profile.targets(clock: clock)?.targetKcal {
            Household.refreshPortions(in: store, mainKcal: kcal, clock: clock)
        }
        let portions = Household.portions(in: store)
        var ctx = try context(profile: profile, preferences: preferences, portions: portions)
        let dayCount = min(max(dayCount, 1), 7)
        ctx.preferences.weeklyBudgetEur *= Double(dayCount) / 7
        ctx.constraints.weeklyBudgetEur *= Double(dayCount) / 7
        ctx.constraints.dayCount = dayCount
        ctx.pantry = Self.resolvedPantry(pantry, resolver: ctx.resolver)
        ctx.recipes = recipes
        ctx.onText = onText
        let week: ValidationResult<WeekPlanDTO>
        do {
            week = try await requestWeek(ctx)
        } catch where error.isRetryable || error.isInfeasible {
            // Repli : une requête par jour en parallèle (research R5). Aussi quand l'IA refuse la semaine
            // entière (réponse jugée trop longue, spec 008) : un jour à la fois, un vrai refus se répète.
            week = try await requestWeekByDays(ctx)
        }
        guard let sanitized = week.sanitized else { throw .invalidOutput("Semaine invalide") }
        let finished = await finish(sanitized.days, ctx: ctx)
        let onTarget = await retryOffTargetDays(finished.days, ctx: ctx)
        let days = SavedRecipeMatcher.restoreSteps(await retryOverBudgetDays(onTarget, ctx: ctx), recipes: ctx.recipes)
        let plan = WeekPlanDTO(prepSessions: sanitized.prepSessions, days: days)
        do {
            try PlanStore.saveWeek(
                plan, startDay: startDay, targets: ctx.targets, createdAt: clock.now, today: clock.today,
                pantry: ctx.pantry, in: store
            )
        } catch {
            throw .unexpected("Enregistrement impossible")
        }
        return Self.finalWarnings(week.warnings, days: days, constraints: ctx.constraints, unverified: finished.unverified)
    }

    private func requestWeek(_ ctx: Context) async throws(AIError) -> ValidationResult<WeekPlanDTO> {
        let client = client
        return try await withBudgetRefusalRecovery { budgetScale, feedback in
            var preferences = ctx.preferences
            preferences.weeklyBudgetEur *= budgetScale
            let input = PromptBuilder.weekInput(
                targets: ctx.targets.macros, goal: ctx.goal, preferences: preferences, feedback: feedback,
                pantry: ctx.pantry, recipes: ctx.recipes, dayCount: ctx.constraints.dayCount
            )
            let data = try await client.generate(
                kind: .week, instructions: PromptBuilder.systemInstructions(), input: input,
                model: ctx.model, apiKey: ctx.apiKey, onText: ctx.onText
            )
            let result = AIOutputValidator.validate(week: try AIResponseDecoder.decodeWeek(data), constraints: ctx.constraints)
            guard result.isValid else { throw AIError.invalidOutput(String(describing: result.fatal)) }
            return result
        }
    }

    private func requestWeekByDays(_ ctx: Context) async throws(AIError) -> ValidationResult<WeekPlanDTO> {
        var days: [DayPlanDTO] = []
        var warnings: [ValidationIssue] = []
        // Chaque jour reçoit sa part du plafond de la période (spec 003, FR-203).
        let dayCount = ctx.constraints.dayCount
        let dayLimit = ctx.constraints.budgetCeilingEur / Double(dayCount)
        do {
            try await withThrowingTaskGroup(of: ValidationResult<DayPlanDTO>.self) { group in
                for offset in 0..<dayCount {
                    group.addTask {
                        try await self.requestDay(
                            ctx, offset: offset, avoid: [], costLimit: dayLimit,
                            recipes: SavedRecipeMatcher.recipes(ctx.recipes, forDay: offset)
                        )
                    }
                }
                for try await result in group {
                    if let day = result.sanitized { days.append(day) }
                    warnings.append(contentsOf: result.warnings)
                }
            }
        } catch {
            throw error as? AIError ?? .unexpected(error.localizedDescription)
        }
        // Semaine reconstituée : contrôle global (jours, budget) sans batch cooking.
        var constraints = ctx.constraints
        constraints.batchCooking = false
        constraints.enforceVariety = false
        var result = AIOutputValidator.validate(week: WeekPlanDTO(prepSessions: [], days: days), constraints: constraints)
        guard result.isValid else { throw .invalidOutput(String(describing: result.fatal)) }
        result.warnings = warnings + result.warnings
        return result
    }

    /// Ingrédients à écouler avec leur code Ciqual, pour les déduire des courses par produit.
    static func resolvedPantry(_ pantry: [IngredientDTO], resolver: NutritionResolver) -> [IngredientDTO] {
        let items = pantry.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.quantity > 0 }
        // Restes proposés par l'application : code déjà connu ; saisies libres rapprochées de Ciqual.
        let typed = items.filter { $0.foodCode == nil }
        guard !typed.isEmpty else { return items }
        let meal = MealDTO(
            type: .lunch, name: "Stock", ingredients: typed, steps: [], prepMinutes: 0, costEur: 0,
            kcal: 0, proteinG: 0, carbsG: 0, fatG: 0, prepSessionRef: nil, time: nil
        )
        return items.filter { $0.foodCode != nil } + resolver.resolve(meal).meal.ingredients
    }

    // MARK: Jour et repas

    func requestDay(
        _ ctx: Context, offset: Int, avoid: [String], prepSessions: Set<Int> = [], costLimit: Double,
        correction: String? = nil, recipes: [MealDTO] = []
    ) async throws(AIError) -> ValidationResult<DayPlanDTO> {
        var dayConstraints = ctx.constraints
        dayConstraints.costLimitEur = costLimit
        let constraints = dayConstraints
        let client = client
        return try await withBudgetRefusalRecovery { budgetScale, feedback in
            var preferences = ctx.preferences
            preferences.weeklyBudgetEur *= budgetScale
            let input = PromptBuilder.dayInput(
                targets: ctx.targets.macros, goal: ctx.goal, preferences: preferences, dayOffset: offset,
                avoidMealNames: avoid, costLimitEur: costLimit * budgetScale,
                feedback: [correction, feedback].compactMap(\.self).joined(separator: " ").nilIfEmpty,
                pantry: ctx.pantry, recipes: recipes
            )
            let data = try await client.generate(
                kind: .day, instructions: PromptBuilder.systemInstructions(), input: input,
                model: ctx.model, apiKey: ctx.apiKey
            )
            let result = AIOutputValidator.validate(
                day: try AIResponseDecoder.decodeDay(data), constraints: constraints,
                expectedOffset: offset, prepSessionIndexes: prepSessions
            )
            guard result.isValid else { throw AIError.invalidOutput(String(describing: result.fatal)) }
            return result
        }
    }

    /// Régénère un jour ; les autres jours restent intacts (US3).
    @discardableResult
    func regenerateDay(
        _ day: DayPlan, profile: Profile, preferences: Preferences, pantry: [IngredientDTO] = [], in store: ModelContext
    ) async throws(AIError) -> [ValidationIssue] {
        guard let plan = day.plan else { throw .unexpected("Jour sans planning") }
        let portions = Household.portions(in: store)
        var ctx = try context(profile: profile, preferences: preferences, portions: portions)
        ctx = Context(
            apiKey: ctx.apiKey, targets: plan.targets ?? ctx.targets, goal: ctx.goal, preferences: ctx.preferences,
            constraints: Self.perPortion(preferences.constraints(targets: (plan.targets ?? ctx.targets).macros), portions),
            model: ctx.model,
            resolver: ctx.resolver, oil: ctx.oil,
            // Ingrédients à écouler choisis pour ce jour, sinon ceux de la semaine.
            pantry: pantry.isEmpty ? plan.pantry : Self.resolvedPantry(pantry, resolver: ctx.resolver)
        )
        let avoid = plan.days.flatMap(\.meals).map(\.name)
        let otherDaysCost = plan.days.filter { $0.persistentModelID != day.persistentModelID }.reduce(0) { $0 + $1.plannedCostEUR }
        let limit = BudgetMath.dayLimit(
            weeklyBudget: Self.periodBudget(preferences, plan: plan) / portions, tolerance: preferences.tolerance,
            otherDaysCost: otherDaysCost
        )
        let result = try await requestDay(
            ctx, offset: day.offset, avoid: avoid, prepSessions: Set(plan.prepSessions.map(\.index)), costLimit: limit
        )
        guard let sanitized = result.sanitized else { throw .invalidOutput("Jour invalide") }
        let finished = await finish([sanitized], ctx: ctx)
        guard var newDay = finished.days.first else { throw .invalidOutput("Jour invalide") }
        // Spec 018 : coût calculé au-dessus de la part du budget restante, un essai moins cher.
        if Self.cost(of: [newDay]) > limit + 0.01,
           let cheaper = await cheaperDay(than: newDay, limit: limit, avoid: avoid, ctx: ctx) {
            newDay = cheaper
        }
        do { try PlanStore.replaceDay(day, with: newDay, in: store) } catch { throw .unexpected("Enregistrement impossible") }
        return Self.finalWarnings(
            result.warnings, days: [newDay], constraints: ctx.constraints, unverified: finished.unverified, includeBudget: false
        )
    }

    /// Remplace un seul repas par une alternative proche en kcal (US3). Renvoie les avertissements.
    @discardableResult
    func replaceMeal(
        _ meal: Meal, profile: Profile, preferences: Preferences, in store: ModelContext
    ) async throws(AIError) -> [ValidationIssue] {
        guard let day = meal.day, let plan = day.plan else { throw .unexpected("Repas sans planning") }
        let portions = Household.portions(in: store)
        let base = try context(profile: profile, preferences: preferences, portions: portions)
        let targets = plan.targets ?? base.targets
        let others = day.sortedMeals.filter { $0.persistentModelID != meal.persistentModelID }.map(\.dto)
        let otherDaysCost = plan.days.filter { $0.persistentModelID != day.persistentModelID }.reduce(0) { $0 + $1.plannedCostEUR }
        let dayLimit = BudgetMath.dayLimit(
            weeklyBudget: Self.periodBudget(preferences, plan: plan) / portions, tolerance: preferences.tolerance,
            otherDaysCost: otherDaysCost
        )
        let mealLimit = BudgetMath.mealLimit(dayLimit: dayLimit, otherMealsCost: others.reduce(0) { $0 + $1.costEur })
        let avoid = plan.days.flatMap(\.meals).map(\.name)
        let constraints = Self.perPortion(preferences.constraints(targets: targets.macros, costLimitEur: mealLimit), portions)
        let sessionIndexes = Set(plan.prepSessions.map(\.index))
        let type = meal.type
        let dayOffset = day.offset
        let client = client
        let result: ValidationResult<MealDTO> = try await withBudgetRefusalRecovery { budgetScale, feedback in
            var preferences = base.preferences
            preferences.weeklyBudgetEur *= budgetScale
            let input = PromptBuilder.replaceMealInput(
                targets: targets.macros, goal: base.goal, preferences: preferences, dayOffset: dayOffset,
                existingDayMeals: others, mealTypeToReplace: type, avoidMealNames: avoid,
                costLimitEur: mealLimit * budgetScale, feedback: feedback
            )
            let data = try await client.generate(
                kind: .meal, instructions: PromptBuilder.systemInstructions(), input: input,
                model: base.model, apiKey: base.apiKey
            )
            let result = AIOutputValidator.validate(
                meal: try AIResponseDecoder.decodeMeal(data), constraints: constraints, expectedType: type
            )
            guard var sanitized = result.sanitized else { throw AIError.invalidOutput(String(describing: result.fatal)) }
            if let ref = sanitized.prepSessionRef, !sessionIndexes.contains(ref) { sanitized.prepSessionRef = nil }
            var checked = result
            checked.sanitized = sanitized
            return checked
        }
        guard let draft = result.sanitized else { throw .invalidOutput("Repas invalide") }
        // Spec 010 : macros Ciqual, portions ajustées aux macros restantes du jour.
        await answerFoodQuestions(for: [draft], ctx: base)
        let (resolved, verified) = resolvedWithParts(draft, resolver: base.resolver)
        let remaining = targets.macros - Totals.planned(others)
        var replacement = PortionAdjuster.adjust([resolved], to: remaining, resolver: base.resolver, oil: base.oil)[0]
        // Étapes écrites pour les quantités d'avant ajustement : réécrites par le rédacteur de recettes.
        if !RecipeConsistency.stepsMatch(replacement) { replacement.steps = [] }
        do { try PlanStore.replaceMeal(meal, with: replacement, in: store) } catch { throw .unexpected("Enregistrement impossible") }
        // Spec 018 : coût calculé par l'application, signalé au-dessus de la part du budget restante.
        let overLimit: [ValidationIssue] = replacement.costEur > mealLimit + 0.01
            ? [.overCostLimit(costEur: BudgetMath.cents(replacement.costEur), limitEur: BudgetMath.cents(mealLimit))] : []
        return result.warnings.filter { !$0.isRecomputed && !$0.isBudget } + overLimit + (verified ? [] : [.unverifiedMeals(count: 1)])
    }

    /// Budget hebdo ramené aux jours du planning (planning de 3 jours : 3/7 du budget).
    static func periodBudget(_ preferences: Preferences, plan: WeeklyPlan) -> Double {
        preferences.weeklyBudget * Double(min(max(plan.days.count, 1), 7)) / 7
    }

    // MARK: Retry

    /// Refus « budget trop bas » de l'IA (spec 008) : nouvel essai avec la raison, puis avec un budget annoncé
    /// doublé. Le coût obtenu reste contrôlé avec le vrai budget : avertissement s'il dépasse, jamais de blocage.
    private func withBudgetRefusalRecovery<T: Sendable>(
        _ operation: @escaping @Sendable (_ budgetScale: Double, _ feedback: String?) async throws -> ValidationResult<T>
    ) async throws(AIError) -> ValidationResult<T> {
        let reason: String
        do throws(AIError) {
            return try await withBudgetRetry { try await operation(1, $0) }
        } catch {
            guard error.isBudgetRefusal, case let .infeasible(text) = error else { throw error }
            reason = text
        }
        let refusal = PromptBuilder.budgetRefusalFeedback(reason: reason)
        do throws(AIError) {
            return try await withBudgetRetry { try await operation(1, $0 ?? refusal) }
        } catch {
            guard error.isBudgetRefusal else { throw error }
        }
        return try await withBudgetRetry { try await operation(2, $0 ?? refusal) }
    }

    /// Coût vérifié après le calcul des prix par l'application (spec 018) : ici, un essai et un nouvel essai
    /// si l'erreur s'y prête.
    private func withBudgetRetry<T: Sendable>(
        _ operation: @escaping @Sendable (String?) async throws -> ValidationResult<T>
    ) async throws(AIError) -> ValidationResult<T> {
        try await withRetry { try await operation(nil) }
    }

    /// Un essai + un nouvel essai si l'erreur s'y prête (research R6).
    private func withRetry<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws(AIError) -> T {
        var lastError = AIError.unexpected("Aucun essai")
        for attempt in 0..<2 {
            do {
                return try await operation()
            } catch {
                let aiError = error as? AIError ?? .unexpected(error.localizedDescription)
                lastError = aiError
                guard aiError.isRetryable, attempt == 0 else { throw aiError }
            }
        }
        throw lastError
    }
}
