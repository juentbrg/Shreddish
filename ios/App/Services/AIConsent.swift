import Foundation

/// Consentement explicite avant le premier envoi à OpenAI (spec 017, FR-1714). Retirable dans les réglages.
enum AIConsent {
    static let key = "aiConsentAt"
    nonisolated(unsafe) static var defaults = UserDefaults.standard

    static var isGranted: Bool { defaults.object(forKey: key) != nil }

    static func grant(at date: Date = .now) { defaults.set(date, forKey: key) }

    static func revoke() { defaults.removeObject(forKey: key) }

    /// Données envoyées, affichées avant l'accord.
    static let sentData = [
        "Tes cibles : calories, protéines, glucides, lipides et ton objectif",
        "Tes préférences : budget, allergies, régimes, aliments aimés ou exclus, équipement, compléments, horaires",
        "Les noms et quantités d'ingrédients des repas à rédiger",
    ]
    /// Données jamais envoyées.
    static let neverSent = [
        "Ton âge, ton sexe, ta taille, ton poids",
        "Ton journal, tes pesées, tes mensurations, tes photos",
        "Tes données Apple Santé",
    ]
}
