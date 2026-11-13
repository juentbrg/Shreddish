import Foundation
import ShreddishCore
import Observation
import SwiftData

/// État partagé de l'app : horloge, services, génération en cours.
@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable {
        case week, journal, shopping, weight, targets
    }

    let clock: any AppClock
    let keyStore: any APIKeyStore
    let client: OpenAIClient
    let generator: PlanGenerator
    /// Recettes rédigées en arrière-plan (spec 010).
    let recipes: RecipeGenerator
    let isUITest: Bool

    var selectedTab: Tab = .week
    /// Génération IA en cours : un seul appel à la fois.
    var busyMessage: String?
    var errorMessage: String?
    var warningMessage: String?
    /// Dernier ajustement de calibration appliqué (spec 002).
    var calibrationMessage: String?

    init(
        clock: any AppClock, keyStore: any APIKeyStore, transport: any AITransport, isUITest: Bool = false,
        matchCache: any FoodMatchCache = InMemoryFoodMatchCache()
    ) {
        self.clock = clock
        self.keyStore = keyStore
        self.isUITest = isUITest
        client = OpenAIClient(transport: transport)
        generator = PlanGenerator(client: client, keyStore: keyStore, clock: clock, matchCache: matchCache)
        recipes = RecipeGenerator(client: client, keyStore: keyStore)
    }

    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        if arguments.contains("-uitest") {
            let key = arguments.contains("-uitest-no-key") ? nil : "sk-uitest-0000"
            return AppModel(
                clock: SystemClock(), keyStore: InMemoryKeyStore(key: key), transport: UITestAITransport(), isUITest: true
            )
        }
        LegacyKeychain.deleteStoredKey()
        return AppModel(
            clock: SystemClock(), keyStore: BundledKeyStore(), transport: URLSessionTransport(),
            matchCache: UserDefaultsFoodMatchCache()
        )
    }

    var hasAPIKey: Bool { keyStore.read() != nil }

    var isBusy: Bool { busyMessage != nil }

    /// Lance une action IA avec indicateur de chargement et message d'erreur lisible ; ensuite, recettes
    /// manquantes rédigées en arrière-plan (spec 010).
    func run(
        _ message: String, recipesIn context: ModelContext? = nil, _ action: () async throws(AIError) -> [ValidationIssue]
    ) async {
        guard !isBusy else { return }
        busyMessage = message
        errorMessage = nil
        warningMessage = nil
        defer { busyMessage = nil }
        do {
            let warnings = try await action()
            warningMessage = Self.describe(warnings)
            if let context { recipes.fillMissing(in: context) }
        } catch {
            errorMessage = error.userMessage
        }
    }

    static func describe(_ warnings: [ValidationIssue]) -> String? {
        var offTarget = 0
        var unverified = 0
        var overBudget: (cost: Double, budget: Double)?
        var overCeiling: (cost: Double, limit: Double)?
        for warning in warnings {
            switch warning {
            case .dayOffTarget: offTarget += 1
            case let .unverifiedMeals(count): unverified += count
            case let .weekOverBudgetWithinTolerance(cost, budget): overBudget = (cost, budget)
            case let .weekOverBudget(cost, ceiling): overCeiling = (cost, ceiling)
            case let .overCostLimit(cost, limit): overCeiling = overCeiling ?? (cost, limit)
            default: break
            }
        }
        var parts: [String] = []
        if offTarget > 0 { parts.append("\(offTarget) jour(s) à plus de 10 % de ta cible") }
        if unverified > 0 { parts.append("\(unverified) repas aux macros estimées par l'IA") }
        if let budget = budgetText(overCeiling: overCeiling, overBudget: overBudget) { parts.append(budget) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ") + ". Signalé(s) dans le planning."
    }

    private static func budgetText(
        overCeiling: (cost: Double, limit: Double)?, overBudget: (cost: Double, budget: Double)?
    ) -> String? {
        if let overCeiling {
            return "courses estimées à \(Format.euros(overCeiling.cost)), au-dessus du plafond de \(Format.euros(overCeiling.limit))"
        }
        if let overBudget {
            let cost = Format.euros(overBudget.cost)
            return "courses estimées à \(cost) pour \(Format.euros(overBudget.budget)) de budget (dans la tolérance)"
        }
        return nil
    }
}
