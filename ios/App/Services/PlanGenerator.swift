import Foundation
import ShreddishCore
import SwiftData

/// Orchestration de la génération : prompt → appel → validation → retry → sauvegarde (research R5, R6).
/// Déclenché seulement par une action de l'utilisateur, jamais en tâche de fond (FR-020).
@MainActor
final class PlanGenerator {
    private let client: OpenAIClient
    private let keyStore: any APIKeyStore
    private let clock: any AppClock

    init(client: OpenAIClient, keyStore: any APIKeyStore, clock: any AppClock) {
        self.client = client
        self.keyStore = keyStore
        self.clock = clock
    }

    struct Context: Sendable {
        let apiKey: String
        let targets: NutritionTargets
        let goal: Goal
        let preferences: PromptPreferences
        let constraints: GenerationConstraints
        let model: String
    }

    private func context(profile: Profile, preferences: Preferences) throws(AIError) -> Context {
        guard let key = keyStore.read() else { throw .missingKey }
        guard let targets = profile.targets(clock: clock) else { throw .unexpected("Profil invalide") }
        let model = preferences.aiModel.trimmingCharacters(in: .whitespaces)
        var promptPreferences = preferences.promptPreferences
        promptPreferences.trainingSessionsPerWeek = profile.training?.sessionsPerWeek
        return Context(
            apiKey: key, targets: targets, goal: profile.goal, preferences: promptPreferences,
            constraints: preferences.constraints(targets: targets.macros),
            model: model.isEmpty ? AIConfig.defaultModel : model
        )
    }

    // MARK: Semaine

    /// Génère et enregistre 7 jours à partir de `startDay` (aujourd'hui par défaut, ou plus tard : spec 006). Renvoie les avertissements (jours hors cible,
    /// semaine au-dessus du budget dans la tolérance).
    @discardableResult
    func generateWeek(
        profile: Profile, preferences: Preferences, startDay: LocalDay? = nil, in store: ModelContext
    ) async throws(AIError) -> [ValidationIssue] {
        let startDay = max(startDay ?? clock.today, clock.today)
        let ctx = try context(profile: profile, preferences: preferences)
        let week: ValidationResult<WeekPlanDTO>
        do {
            week = try await requestWeek(ctx)
        } catch where error.isRetryable {
            // Repli : 7 requêtes d'un jour en parallèle (research R5).
            week = try await requestWeekByDays(ctx)
        }
        guard let sanitized = week.sanitized else { throw .invalidOutput("Semaine invalide") }
        do {
            try PlanStore.saveWeek(
                sanitized, startDay: startDay, targets: ctx.targets, createdAt: clock.now, today: clock.today, in: store
            )
        } catch {
            throw .unexpected("Enregistrement impossible")
        }
        return week.warnings
    }

    private func requestWeek(_ ctx: Context) async throws(AIError) -> ValidationResult<WeekPlanDTO> {
        let client = client
        return try await withBudgetRetry { feedback in
            let input = PromptBuilder.weekInput(
                targets: ctx.targets.macros, goal: ctx.goal, preferences: ctx.preferences, feedback: feedback
            )
            let data = try await client.generate(
                kind: .week, instructions: PromptBuilder.systemInstructions(), input: input,
                model: ctx.model, apiKey: ctx.apiKey
            )
            let result = AIOutputValidator.validate(week: try AIResponseDecoder.decodeWeek(data), constraints: ctx.constraints)
            guard result.isValid else { throw AIError.invalidOutput(String(describing: result.fatal)) }
            return result
        }
    }

    private func requestWeekByDays(_ ctx: Context) async throws(AIError) -> ValidationResult<WeekPlanDTO> {
        var days: [DayPlanDTO] = []
        var warnings: [ValidationIssue] = []
        // Chaque jour reçoit un septième du plafond de la semaine (spec 003, FR-203).
        let dayLimit = ctx.constraints.budgetCeilingEur / 7
        do {
            try await withThrowingTaskGroup(of: ValidationResult<DayPlanDTO>.self) { group in
                for offset in 0...6 {
                    group.addTask { try await self.requestDay(ctx, offset: offset, avoid: [], costLimit: dayLimit) }
                }
                for try await result in group {
                    if let day = result.sanitized { days.append(day) }
                    warnings.append(contentsOf: result.warnings)
                }
            }
        } catch {
            throw error as? AIError ?? .unexpected(error.localizedDescription)
        }
        // Semaine reconstituée : contrôle global (7 jours, budget) sans batch cooking.
        var constraints = ctx.constraints
        constraints.batchCooking = false
        var result = AIOutputValidator.validate(week: WeekPlanDTO(prepSessions: [], days: days), constraints: constraints)
        guard result.isValid else { throw .invalidOutput(String(describing: result.fatal)) }
        result.warnings = warnings + result.warnings
        return result
    }

    // MARK: Jour et repas

    private func requestDay(
        _ ctx: Context, offset: Int, avoid: [String], prepSessions: Set<Int> = [], costLimit: Double
    ) async throws(AIError) -> ValidationResult<DayPlanDTO> {
        var dayConstraints = ctx.constraints
        dayConstraints.costLimitEur = costLimit
        let constraints = dayConstraints
        let client = client
        return try await withBudgetRetry { feedback in
            let input = PromptBuilder.dayInput(
                targets: ctx.targets.macros, goal: ctx.goal, preferences: ctx.preferences, dayOffset: offset,
                avoidMealNames: avoid, costLimitEur: costLimit, feedback: feedback
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
        _ day: DayPlan, profile: Profile, preferences: Preferences, in store: ModelContext
    ) async throws(AIError) -> [ValidationIssue] {
        guard let plan = day.plan else { throw .unexpected("Jour sans planning") }
        var ctx = try context(profile: profile, preferences: preferences)
        ctx = Context(
            apiKey: ctx.apiKey, targets: plan.targets ?? ctx.targets, goal: ctx.goal, preferences: ctx.preferences,
            constraints: preferences.constraints(targets: (plan.targets ?? ctx.targets).macros), model: ctx.model
        )
        let avoid = plan.days.flatMap(\.meals).map(\.name)
        let otherDaysCost = plan.days.filter { $0.persistentModelID != day.persistentModelID }.reduce(0) { $0 + $1.plannedCostEUR }
        let limit = BudgetMath.dayLimit(
            weeklyBudget: preferences.weeklyBudget, tolerance: preferences.tolerance, otherDaysCost: otherDaysCost
        )
        let result = try await requestDay(
            ctx, offset: day.offset, avoid: avoid, prepSessions: Set(plan.prepSessions.map(\.index)), costLimit: limit
        )
        guard let sanitized = result.sanitized else { throw .invalidOutput("Jour invalide") }
        do { try PlanStore.replaceDay(day, with: sanitized, in: store) } catch { throw .unexpected("Enregistrement impossible") }
        return result.warnings
    }

    /// Remplace un seul repas par une alternative proche en kcal (US3). Renvoie les avertissements.
    @discardableResult
    func replaceMeal(
        _ meal: Meal, profile: Profile, preferences: Preferences, in store: ModelContext
    ) async throws(AIError) -> [ValidationIssue] {
        guard let day = meal.day, let plan = day.plan else { throw .unexpected("Repas sans planning") }
        let base = try context(profile: profile, preferences: preferences)
        let targets = plan.targets ?? base.targets
        let others = day.sortedMeals.filter { $0.persistentModelID != meal.persistentModelID }.map(\.dto)
        let otherDaysCost = plan.days.filter { $0.persistentModelID != day.persistentModelID }.reduce(0) { $0 + $1.plannedCostEUR }
        let dayLimit = BudgetMath.dayLimit(
            weeklyBudget: preferences.weeklyBudget, tolerance: preferences.tolerance, otherDaysCost: otherDaysCost
        )
        let mealLimit = BudgetMath.mealLimit(dayLimit: dayLimit, otherMealsCost: others.reduce(0) { $0 + $1.costEur })
        let avoid = plan.days.flatMap(\.meals).map(\.name)
        let constraints = preferences.constraints(targets: targets.macros, costLimitEur: mealLimit)
        let sessionIndexes = Set(plan.prepSessions.map(\.index))
        let type = meal.type
        let dayOffset = day.offset
        let client = client
        let result: ValidationResult<MealDTO> = try await withBudgetRetry { feedback in
            let input = PromptBuilder.replaceMealInput(
                targets: targets.macros, goal: base.goal, preferences: base.preferences, dayOffset: dayOffset,
                existingDayMeals: others, mealTypeToReplace: type, avoidMealNames: avoid, costLimitEur: mealLimit,
                feedback: feedback
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
        guard let replacement = result.sanitized else { throw .invalidOutput("Repas invalide") }
        do { try PlanStore.replaceMeal(meal, with: replacement, in: store) } catch { throw .unexpected("Enregistrement impossible") }
        return result.warnings
    }

    // MARK: Retry

    /// Budget souple (spec 004, FR-304) : au-dessus du plafond, un nouvel essai avec le coût obtenu ;
    /// la proposition la moins chère est gardée, avec son avertissement.
    private func withBudgetRetry<T: Sendable>(
        _ operation: @escaping @Sendable (String?) async throws -> ValidationResult<T>
    ) async throws(AIError) -> ValidationResult<T> {
        let first = try await withRetry { try await operation(nil) }
        guard let over = first.overCeiling else { return first }
        let feedback = PromptBuilder.overBudgetFeedback(costEur: over.costEur, ceilingEur: over.limitEur)
        let second: ValidationResult<T>
        do {
            second = try await withRetry { try await operation(feedback) }
        } catch {
            return first
        }
        return (second.overCeiling?.costEur ?? 0) <= over.costEur ? second : first
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
