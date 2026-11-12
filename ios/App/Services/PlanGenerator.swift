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
        return Context(
            apiKey: key, targets: targets, goal: profile.goal, preferences: preferences.promptPreferences,
            constraints: preferences.constraints(targets: targets.macros),
            model: model.isEmpty ? AIConfig.defaultModel : model
        )
    }

    // MARK: Semaine

    /// Génère et enregistre 7 jours à partir d'aujourd'hui. Renvoie les avertissements (jours hors cible
    /// ou hors budget).
    @discardableResult
    func generateWeek(profile: Profile, preferences: Preferences, in store: ModelContext) async throws(AIError) -> [ValidationIssue] {
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
            try PlanStore.saveWeek(sanitized, startDay: clock.today, targets: ctx.targets, createdAt: clock.now, in: store)
        } catch {
            throw .unexpected("Enregistrement impossible")
        }
        return week.warnings
    }

    private func requestWeek(_ ctx: Context) async throws(AIError) -> ValidationResult<WeekPlanDTO> {
        let input = PromptBuilder.weekInput(targets: ctx.targets.macros, goal: ctx.goal, preferences: ctx.preferences)
        let client = client
        return try await withRetry {
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
        do {
            try await withThrowingTaskGroup(of: ValidationResult<DayPlanDTO>.self) { group in
                for offset in 0...6 {
                    group.addTask { try await self.requestDay(ctx, offset: offset, avoid: []) }
                }
                for try await result in group {
                    if let day = result.sanitized { days.append(day) }
                    warnings.append(contentsOf: result.warnings)
                }
            }
        } catch {
            throw error as? AIError ?? .unexpected(error.localizedDescription)
        }
        var result = ValidationResult<WeekPlanDTO>()
        result.warnings = warnings
        result.sanitized = WeekPlanDTO(prepSessions: [], days: days.sorted { $0.dayOffset < $1.dayOffset })
        return result
    }

    // MARK: Jour et repas

    private func requestDay(
        _ ctx: Context, offset: Int, avoid: [String], prepSessions: Set<Int> = []
    ) async throws(AIError) -> ValidationResult<DayPlanDTO> {
        let input = PromptBuilder.dayInput(
            targets: ctx.targets.macros, goal: ctx.goal, preferences: ctx.preferences, dayOffset: offset, avoidMealNames: avoid
        )
        let client = client
        return try await withRetry {
            let data = try await client.generate(
                kind: .day, instructions: PromptBuilder.systemInstructions(), input: input,
                model: ctx.model, apiKey: ctx.apiKey
            )
            let result = AIOutputValidator.validate(
                day: try AIResponseDecoder.decodeDay(data), constraints: ctx.constraints,
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
        let result = try await requestDay(
            ctx, offset: day.offset, avoid: avoid, prepSessions: Set(plan.prepSessions.map(\.index))
        )
        guard let sanitized = result.sanitized else { throw .invalidOutput("Jour invalide") }
        do { try PlanStore.replaceDay(day, with: sanitized, in: store) } catch { throw .unexpected("Enregistrement impossible") }
        return result.warnings
    }

    /// Remplace un seul repas par une alternative proche en kcal (US3).
    func replaceMeal(_ meal: Meal, profile: Profile, preferences: Preferences, in store: ModelContext) async throws(AIError) {
        guard let day = meal.day, let plan = day.plan else { throw .unexpected("Repas sans planning") }
        let base = try context(profile: profile, preferences: preferences)
        let targets = plan.targets ?? base.targets
        let others = day.sortedMeals.filter { $0.persistentModelID != meal.persistentModelID }.map(\.dto)
        let input = PromptBuilder.replaceMealInput(
            targets: targets.macros, goal: base.goal, preferences: base.preferences, dayOffset: day.offset,
            existingDayMeals: others, mealTypeToReplace: meal.type,
            avoidMealNames: plan.days.flatMap(\.meals).map(\.name)
        )
        let constraints = preferences.constraints(targets: targets.macros)
        let sessionIndexes = Set(plan.prepSessions.map(\.index))
        let type = meal.type
        let client = client
        let replacement: MealDTO = try await withRetry {
            let data = try await client.generate(
                kind: .meal, instructions: PromptBuilder.systemInstructions(), input: input,
                model: base.model, apiKey: base.apiKey
            )
            let result = AIOutputValidator.validate(
                meal: try AIResponseDecoder.decodeMeal(data), constraints: constraints, expectedType: type
            )
            guard var sanitized = result.sanitized else { throw AIError.invalidOutput(String(describing: result.fatal)) }
            if let ref = sanitized.prepSessionRef, !sessionIndexes.contains(ref) { sanitized.prepSessionRef = nil }
            return sanitized
        }
        do { try PlanStore.replaceMeal(meal, with: replacement, in: store) } catch { throw .unexpected("Enregistrement impossible") }
    }

    // MARK: Retry

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
