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
        String(localized: "Tes cibles : calories, protéines, glucides, lipides et ton objectif"),
        String(localized: "Tes préférences : budget, allergies, régimes, aliments aimés ou exclus, équipement, compléments, horaires"),
        String(localized: "Les noms et quantités d'ingrédients des repas à rédiger"),
    ]
    /// Données jamais envoyées.
    static let neverSent = [
        String(localized: "Ton âge, ton sexe, ta taille, ton poids"),
        String(localized: "Ton journal, tes pesées, tes mensurations, tes photos"),
        String(localized: "Tes données Apple Santé"),
    ]
}
