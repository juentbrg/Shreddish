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

    /// Message en français pour l'utilisateur.
    public var userMessage: String {
        switch self {
        case .missingKey: "Ajoute ta clé API OpenAI dans Profil → Clé API pour générer des repas."
        case .invalidKey: "Clé API refusée par OpenAI. Vérifie-la dans Profil → Clé API."
        case .rateLimited: "Quota OpenAI atteint ou trop de requêtes. Réessaie plus tard ou vérifie ton crédit."
        case .offline: "Pas de connexion internet. Ton planning actuel reste disponible."
        case .timeout: "OpenAI met trop de temps à répondre. Réessaie dans un instant."
        case let .server(status): "OpenAI est indisponible (erreur \(status)). Réessaie dans un instant."
        case .incomplete: "Réponse incomplète de l'IA. Réessaie."
        case .invalidOutput: "L'IA a renvoyé un planning invalide. Réessaie."
        case let .infeasible(reason): "Contraintes impossibles à respecter : \(reason)"
        case .cancelled: "Génération annulée."
        case let .unexpected(detail): "Erreur inattendue : \(detail)"
        }
    }
}
