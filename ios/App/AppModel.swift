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
    let isUITest: Bool

    var selectedTab: Tab = .week
    /// Génération IA en cours : un seul appel à la fois.
    var busyMessage: String?
    var errorMessage: String?
    var warningMessage: String?
    /// Dernier ajustement de calibration appliqué (spec 002).
    var calibrationMessage: String?
    /// Incrémenté quand la clé change, pour rafraîchir les vues qui l'affichent.
    var keyRevision = 0

    init(clock: any AppClock, keyStore: any APIKeyStore, transport: any AITransport, isUITest: Bool = false) {
        self.clock = clock
        self.keyStore = keyStore
        self.isUITest = isUITest
        client = OpenAIClient(transport: transport)
        generator = PlanGenerator(client: client, keyStore: keyStore, clock: clock)
    }

    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        if arguments.contains("-uitest") {
            let key = arguments.contains("-uitest-no-key") ? nil : "sk-uitest-0000"
            return AppModel(
                clock: SystemClock(), keyStore: InMemoryKeyStore(key: key), transport: UITestAITransport(), isUITest: true
            )
        }
        let keychain = KeychainStore()
        keychain.seedDevelopmentKeyIfNeeded()
        return AppModel(clock: SystemClock(), keyStore: keychain, transport: URLSessionTransport())
    }

    var hasAPIKey: Bool {
        _ = keyRevision
        return keyStore.read() != nil
    }

    var isBusy: Bool { busyMessage != nil }

    /// Lance une action IA avec indicateur de chargement et message d'erreur lisible.
    func run(_ message: String, _ action: () async throws(AIError) -> [ValidationIssue]) async {
        guard !isBusy else { return }
        busyMessage = message
        errorMessage = nil
        warningMessage = nil
        defer { busyMessage = nil }
        do {
            let warnings = try await action()
            warningMessage = Self.describe(warnings)
        } catch {
            errorMessage = error.userMessage
        }
    }

    static func describe(_ warnings: [ValidationIssue]) -> String? {
        var offTarget = 0
        var overBudget = 0
        for warning in warnings {
            switch warning {
            case .dayOffTarget: offTarget += 1
            case .dayOverBudget: overBudget += 1
            default: break
            }
        }
        var parts: [String] = []
        if offTarget > 0 { parts.append("\(offTarget) jour(s) à plus de 10 % de ta cible") }
        if overBudget > 0 { parts.append("\(overBudget) jour(s) au-dessus du budget") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ") + ". Signalé(s) dans le planning."
    }
}
