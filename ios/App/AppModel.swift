import Foundation
import ShreddishCore
import Observation
import SwiftData

/// Longueur déjà relue du texte reçu en flux.
final class StreamProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var parsed = 0

    func shouldParse(length: Int) -> Bool {
        lock.withLock {
            guard length - parsed >= 400 else { return false }
            parsed = length
            return true
        }
    }
}

/// Repas d'un planning actif : jour et rang.
struct MealRef: Hashable {
    let dayKey: Int
    let order: Int
}

/// Écran ouvert au toucher d'un rappel (spec 016).
enum DeepLink: Hashable {
    case meal(MealRef)
    case planNext
    /// Sessions de batch cooking du planning qui commence ce jour.
    case prep(planStartKey: Int)
    case weighIn
    case shopping
}

/// Sessions de batch cooking d'un planning, pour la pile de navigation.
struct PrepRoute: Hashable {
    let planStartKey: Int
}

/// Pesée dans « Modifier mon profil », pour la pile de navigation.
struct WeighInRoute: Hashable {}

/// État partagé de l'app : horloge, services, génération en cours.
@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable {
        case week, journal, shopping, recipes, targets
    }

    let clock: any AppClock
    let keyStore: any APIKeyStore
    let client: OpenAIClient
    let generator: PlanGenerator
    /// Recettes rédigées en arrière-plan (spec 010).
    let recipes: RecipeGenerator
    /// Rappels locaux (spec 016).
    let notifications: NotificationService
    /// Abonnement (spec 017).
    let subscriptions: SubscriptionStore
    /// Génération demandée sans abonnement après la semaine offerte : écran d'abonnement.
    var needsPaywall = false
    /// Réseau : bandeau hors ligne, reprise des actions en attente (spec 017).
    let network: NetworkMonitor
    /// Apple Watch (spec 017).
    let watch: WatchBridge
    /// Apple Santé, désactivé par défaut (spec 017).
    let health: HealthService
    /// Produits emballés par code-barres (journal rapide, spec 017).
    let packagedFoods = OpenFoodFactsClient(transport: URLSessionTransport())
    let isUITest: Bool

    var selectedTab: Tab = .week
    /// Action IA demandée sans consentement : écran d'accord affiché (spec 017).
    var needsAIConsent = false
    /// Écran à ouvrir (toucher d'un rappel), consommé par l'onglet concerné.
    var deepLink: DeepLink?
    /// Génération IA en cours : un seul appel à la fois.
    var busyMessage: String?
    /// Plats déjà reçus pendant la génération d'une semaine, affichés en direct (spec 017).
    var liveMeals: [String] = []
    var errorMessage: String?
    var warningMessage: String?
    /// Dernier repas remplacé à la main : on peut le remettre (appui involontaire, objet tombé sur l'écran).
    var undoableReplacement: ReplacedMeal?
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
        notifications = NotificationService(enabled: !isUITest)
        health = HealthService(enabled: !isUITest)
        network = NetworkMonitor(enabled: !isUITest)
        watch = WatchBridge(enabled: !isUITest)
        #if DEBUG
        subscriptions = SubscriptionStore(enforced: false)
        #else
        subscriptions = SubscriptionStore(enforced: !isUITest)
        #endif
    }

    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        if arguments.contains("-uitest") {
            AIConsent.defaults = UserDefaults(suiteName: "uitest") ?? .standard
            if !arguments.contains("-uitest-no-consent") { AIConsent.grant() } else { AIConsent.revoke() }
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
        _ message: String, recipesIn context: ModelContext? = nil,
        _ action: @escaping () async throws(AIError) -> [ValidationIssue]
    ) async {
        guard !isBusy else { return }
        guard AIConsent.isGranted else {
            // Laisse se fermer la feuille ou le menu qui a lancé l'action : une seule feuille à la fois.
            try? await Task.sleep(for: .milliseconds(700))
            needsAIConsent = true
            return
        }
        // Droits relus avant de refuser : au lancement, ceux déjà acquis ne sont pas encore chargés.
        if !subscriptions.hasAccess { await subscriptions.refresh() }
        guard subscriptions.hasAccess else {
            try? await Task.sleep(for: .milliseconds(700))
            needsPaywall = true
            return
        }
        busyMessage = message
        errorMessage = nil
        warningMessage = nil
        defer {
            busyMessage = nil
            liveMeals = []
        }
        do {
            let warnings = try await action()
            subscriptions.freeWeekUsed = true
            warningMessage = Self.describe(warnings)
            if let context { recipes.fillMissing(in: context) }
            await notifications.reschedule()
        } catch {
            if error == .offline || (error == .timeout && !network.isOnline) {
                // Hors ligne : rien n'est perdu, l'action repart au retour du réseau (spec 017, FR-1702).
                pending = PendingRun(message: message, context: context, action: action)
                let action = message.replacingOccurrences(of: "…", with: "")
                warningMessage = String(localized: "Hors ligne : « \(action) » reprendra au retour du réseau.")
            } else {
                errorMessage = error.userMessage
            }
        }
    }

    /// Action IA interrompue faute de réseau.
    struct PendingRun {
        let message: String
        let context: ModelContext?
        let action: () async throws(AIError) -> [ValidationIssue]
    }

    private(set) var pending: PendingRun?

    /// Réseau revenu : action en attente relancée.
    func resumePending() async {
        guard let pending, !isBusy else { return }
        self.pending = nil
        await run(pending.message, recipesIn: pending.context, pending.action)
    }

    /// Rappel pour le flux de la semaine : plats reçus publiés sur l'acteur principal.
    var liveMealsHandler: @Sendable (String) -> Void {
        // Relecture tous les ~400 caractères : des milliers de deltas par semaine.
        let progress = StreamProgress()
        return { [weak self] text in
            guard progress.shouldParse(length: text.utf8.count) else { return }
            let names = LiveMeals.names(in: text)
            Task { @MainActor in
                guard let self, names.count != self.liveMeals.count else { return }
                self.liveMeals = names
            }
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
        if offTarget > 0 { parts.append(String(localized: "\(offTarget) jour(s) à plus de 10 % de ta cible")) }
        if unverified > 0 { parts.append(String(localized: "\(unverified) repas aux macros estimées par l'IA")) }
        if let budget = budgetText(overCeiling: overCeiling, overBudget: overBudget) { parts.append(budget) }
        parts += warnings.contains(.batchCookingSkipped)
            ? [String(localized: "pas de batch cooking cette semaine (planning fait jour par jour)")] : []
        return parts.isEmpty ? nil : String(localized: "\(parts.joined(separator: " · ")). Signalé(s) dans le planning.")
    }

    private static func budgetText(
        overCeiling: (cost: Double, limit: Double)?, overBudget: (cost: Double, budget: Double)?
    ) -> String? {
        if let overCeiling {
            let cost = Format.euros(overCeiling.cost)
            let limit = Format.euros(overCeiling.limit)
            return String(localized: "courses estimées à \(cost), au-dessus du plafond de \(limit)")
        }
        if let overBudget {
            let cost = Format.euros(overBudget.cost)
            return String(localized: "courses estimées à \(cost) pour \(Format.euros(overBudget.budget)) de budget (dans la tolérance)")
        }
        return nil
    }
}

/// Repas d'avant un remplacement : jour, rang, contenu et statut.
/// Repas remplacé, pour « Remettre l'ancien repas » : nouveau repas visé par son identifiant, jamais par son rang
/// (un jour régénéré entre-temps ne doit pas être écrasé).
struct ReplacedMeal {
    let dayID: PersistentIdentifier
    var replacementID: PersistentIdentifier?
    let previous: MealDTO
    let status: MealStatus
    let eatenFraction: Double?
    let statusChangedAt: Date?
}
