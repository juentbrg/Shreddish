import Foundation

/// Erreurs de génération IA (contracts/ai-requests.md, tableau « Erreurs »).
public enum AIError: Error, Equatable, Sendable {
    case missingKey
    case invalidKey
    case rateLimited
    case offline
    case timeout
    case server(status: Int)
    /// Réponse `incomplete` ou refus du modèle.
    case incomplete
    /// JSON invalide ou validation locale en échec après retry.
    case invalidOutput(String)
    /// Contraintes impossibles signalées par l'IA ; raison affichée telle quelle.
    case infeasible(String)
    case cancelled
    case unexpected(String)

    /// Erreurs pour lesquelles un nouvel essai automatique a un sens.
    public var isRetryable: Bool {
        switch self {
        case .timeout, .server, .incomplete, .invalidOutput: true
        default: false
        }
    }

    /// Refus de l'IA, quelle qu'en soit la raison.
    public var isInfeasible: Bool {
        if case .infeasible = self { true } else { false }
    }

    /// Refus de l'IA motivé par le prix : jamais bloquant, le budget est souple (spec 008).
    public var isBudgetRefusal: Bool {
        guard case let .infeasible(reason) = self else { return false }
        let text = TextNormalizer.basic(reason)
        return ["budget", "€", "euro", "prix", "cout", "plafond", "cher", "argent"].contains { text.contains($0) }
    }

    /// Message pour l'utilisateur, dans la langue de l'appareil.
    public var userMessage: String {
        switch self {
        case .missingKey: String(localized: "Clé API absente du build : renseigne OPENAI_API_KEY dans Config/Secrets.xcconfig.",
            bundle: .module)
        case .invalidKey: String(localized: "Clé API refusée par OpenAI : remplace-la dans Config/Secrets.xcconfig.", bundle: .module)
        case .rateLimited:
            String(localized: "Quota OpenAI atteint ou trop de requêtes. Réessaie plus tard ou vérifie ton crédit.", bundle: .module)
        case .offline: String(localized: "Pas de connexion internet. Ton planning actuel reste disponible.", bundle: .module)
        case .timeout: String(localized: "OpenAI met trop de temps à répondre. Réessaie dans un instant.", bundle: .module)
        case let .server(status): String(localized: "OpenAI est indisponible (erreur \(status)). Réessaie dans un instant.",
            bundle: .module)
        case .incomplete: String(localized: "Réponse incomplète de l'IA. Réessaie.", bundle: .module)
        case .invalidOutput: String(localized: "L'IA a renvoyé un planning invalide. Réessaie.", bundle: .module)
        case let .infeasible(reason): String(localized: "Contraintes impossibles à respecter : \(reason)", bundle: .module)
        case .cancelled: String(localized: "Génération annulée.", bundle: .module)
        case let .unexpected(detail): String(localized: "Erreur inattendue : \(detail)", bundle: .module)
        }
    }
}
