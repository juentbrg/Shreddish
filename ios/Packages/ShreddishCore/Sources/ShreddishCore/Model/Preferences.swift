import Foundation
import SwiftData

/// Préférences de génération (FR-007, FR-008 ; spec 003), singleton.
@Model
public final class Preferences {
    public static let mealsPerDayRange = 2...5
    public static let maxPrepMinutesRange = 5...90
    public static let weeklyBudgetRange = 20.0...300.0
    public static let toleranceOptions = [0.0, 0.05, 0.10, 0.15, 0.20]
    public static let defaultTolerance = 0.10
    /// Modèle OpenAI par défaut (research R4), modifiable dans Préférences.
    public static let defaultAIModel = "gpt-6-luna"
    /// Anciens défauts remplacés par `defaultAIModel` au lancement (choix explicite conservé sinon).
    public static let legacyDefaultAIModels: Set<String> = ["gpt-5-mini"]

    /// Passe l'ancien modèle par défaut au nouveau. Retourne vrai si modifié.
    @discardableResult
    public func upgradeLegacyDefaultModel() -> Bool {
        guard Self.legacyDefaultAIModels.contains(aiModel) else { return false }
        aiModel = Self.defaultAIModel
        return true
    }

    /// 2-5, collations incluses. Défaut 4 (3 repas + 1 collation).
    public var mealsPerDay: Int
    /// 5-90 min. Défaut 20.
    public var maxPrepMinutes: Int
    /// Budget par jour de la v1 ; sert de défaut au budget hebdo (× 7) pour les préférences migrées.
    public var dailyBudgetEUR: Double
    /// Aliments que l'utilisateur n'aime pas (jamais proposés).
    public var excludedFoods: [String]
    public var likedFoods: [String]
    public var equipment: [String]
    /// FR-014, désactivé par défaut.
    public var batchCooking: Bool
    public var aiModel: String
    // Spec 003 (SchemaV3), optionnels pour la migration légère.
    public var weeklyBudgetEUR: Double?
    public var budgetTolerance: Double?
    public var allergies: [String]?
    public var ingredientAvailabilityRaw: String?
    /// Obsolète (spec 011, prix France sans magasin) : conservé pour la migration.
    public var storeRaw: String?
    /// Obsolète (spec 011).
    public var customStoreName: String?
    // Spec 004 (SchemaV4).
    /// Compléments possédés (whey, créatine…) : intégrés aux repas, coût 0, hors liste de courses.
    public var supplements: [String]?
    /// Heure d'entraînement habituelle, en minutes depuis minuit ; nil = non précisée.
    public var trainingTimeMinutes: Int?
    // Spec 005 (SchemaV5).
    /// Obsolète (spec 011, prix France sans ville) : conservé pour la migration.
    public var city: String?
    // Spec 007 (SchemaV6).
    /// `[clé normalisée: SupplementInfo]` encodé : protéines par dose et taille de dose.
    public var supplementInfoData: Data?

    public init() {
        mealsPerDay = 4
        maxPrepMinutes = 20
        dailyBudgetEUR = 8
        excludedFoods = []
        likedFoods = []
        equipment = []
        batchCooking = false
        aiModel = Self.defaultAIModel
        weeklyBudgetEUR = 56
        budgetTolerance = Self.defaultTolerance
    }

    /// Budget courses de la semaine (FR-201).
    public var weeklyBudget: Double {
        get { weeklyBudgetEUR ?? dailyBudgetEUR * 7 }
        set { weeklyBudgetEUR = newValue }
    }

    /// Dépassement toléré, 0 à 0,20 (FR-201).
    public var tolerance: Double {
        get { budgetTolerance ?? Self.defaultTolerance }
        set { budgetTolerance = newValue }
    }

    /// Plafond : budget × (1 + tolérance).
    public var budgetCeiling: Double { weeklyBudget * (1 + tolerance) }

    public var allergyList: [String] {
        get { allergies ?? [] }
        set { allergies = newValue }
    }

    public var supplementList: [String] {
        get { supplements ?? [] }
        set { supplements = newValue }
    }

    /// Détail d'un complément (protéines par dose, dose), vide si non précisé.
    public func supplementInfo(for name: String) -> SupplementInfo {
        supplementInfoMap[TextNormalizer.singular(name)] ?? SupplementInfo()
    }

    public func setSupplementInfo(_ info: SupplementInfo, for name: String) {
        var map = supplementInfoMap
        map[TextNormalizer.singular(name)] = info.isEmpty ? nil : info
        supplementInfoData = map.isEmpty ? nil : try? JSONEncoder().encode(map)
    }

    private var supplementInfoMap: [String: SupplementInfo] {
        supplementInfoData.flatMap { try? JSONDecoder().decode([String: SupplementInfo].self, from: $0) } ?? [:]
    }

    /// Compléments possédés avec leur détail, tels qu'envoyés à l'IA.
    public var ownedSupplementDetails: [OwnedSupplement] {
        supplementList.map { name in
            OwnedSupplement(name: name, info: supplementInfo(for: name))
        }
    }

    /// « HH:mm » ou nil.
    public var trainingTimeLabel: String? {
        trainingTimeMinutes.map { String(format: "%02d:%02d", $0 / 60 % 24, $0 % 60) }
    }

    public var availability: IngredientAvailability {
        get { ingredientAvailabilityRaw.flatMap(IngredientAvailability.init(rawValue:)) ?? .everywhere }
        set { ingredientAvailabilityRaw = newValue.rawValue }
    }

    public var promptPreferences: PromptPreferences {
        PromptPreferences(
            mealsPerDay: mealsPerDay, maxPrepMinutes: maxPrepMinutes, weeklyBudgetEur: weeklyBudget,
            budgetTolerance: tolerance, allergies: allergyList, dislikedFoods: excludedFoods, likedFoods: likedFoods,
            equipment: equipment, batchCooking: batchCooking, ingredientAvailability: availability,
            ownedSupplements: ownedSupplementDetails, trainingTime: trainingTimeLabel
        )
    }

    public func constraints(targets: MacroTotals, costLimitEur: Double? = nil) -> GenerationConstraints {
        GenerationConstraints(
            targets: targets, mealsPerDay: mealsPerDay, maxPrepMinutes: maxPrepMinutes,
            weeklyBudgetEur: weeklyBudget, budgetTolerance: tolerance, batchCooking: batchCooking,
            allergies: allergyList, excludedFoods: excludedFoods, costLimitEur: costLimitEur,
            ownedSupplements: supplementList
        )
    }
}

/// Nature d'un complément : il apporte des macros (whey, gainer) ou se prend en dose simple (créatine, vitamines).
public enum SupplementKind: String, Codable, Sendable, CaseIterable {
    case macro
    case dose

    /// Devine la nature depuis le nom ; modifiable par l'utilisateur.
    public static func infer(from name: String) -> SupplementKind {
        let key = TextNormalizer.basic(name)
        let macroWords = ["whey", "protein", "proteine", "caseine", "casein", "gainer", "barre", "isolat", "mass"]
        return macroWords.contains { key.contains($0) } ? .macro : .dose
    }
}

/// Unité d'une dose simple.
public enum SupplementUnit: String, Codable, Sendable, CaseIterable {
    case g, mg, µg, ml, gelule, comprime, sachet
}

/// Détail d'un complément possédé (spec 007).
public struct SupplementInfo: Codable, Sendable, Equatable {
    /// Nature choisie ; nil = déduite du nom.
    public var kind: SupplementKind?
    // Complément à macros, valeurs par dose.
    /// Taille d'une dose, en g (ex. 30 g, un scoop).
    public var servingG: Double?
    public var kcalPerServing: Double?
    /// Protéines par dose, en g (ex. 24 g pour une whey).
    public var proteinPerServingG: Double?
    public var carbsPerServingG: Double?
    public var fatPerServingG: Double?
    // Dose simple.
    /// Quantité par prise (ex. 5 pour 5 g de créatine).
    public var doseAmount: Double?
    public var doseUnit: SupplementUnit?
    public var dosesPerDay: Int?

    public init(
        kind: SupplementKind? = nil, servingG: Double? = nil, kcalPerServing: Double? = nil,
        proteinPerServingG: Double? = nil, carbsPerServingG: Double? = nil, fatPerServingG: Double? = nil,
        doseAmount: Double? = nil, doseUnit: SupplementUnit? = nil, dosesPerDay: Int? = nil
    ) {
        self.kind = kind
        self.servingG = servingG
        self.kcalPerServing = kcalPerServing
        self.proteinPerServingG = proteinPerServingG
        self.carbsPerServingG = carbsPerServingG
        self.fatPerServingG = fatPerServingG
        self.doseAmount = doseAmount
        self.doseUnit = doseUnit
        self.dosesPerDay = dosesPerDay
    }

    public var isEmpty: Bool { self == SupplementInfo() }

    public func resolvedKind(for name: String) -> SupplementKind { kind ?? SupplementKind.infer(from: name) }
}
