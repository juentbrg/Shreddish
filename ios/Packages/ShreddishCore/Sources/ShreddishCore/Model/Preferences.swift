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
    public var storeRaw: String?
    public var customStoreName: String?
    // Spec 004 (SchemaV4).
    /// Compléments possédés (whey, créatine…) : intégrés aux repas, coût 0, hors liste de courses.
    public var supplements: [String]?
    /// Heure d'entraînement habituelle, en minutes depuis minuit ; nil = non précisée.
    public var trainingTimeMinutes: Int?

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

    /// « HH:mm » ou nil.
    public var trainingTimeLabel: String? {
        trainingTimeMinutes.map { String(format: "%02d:%02d", $0 / 60 % 24, $0 % 60) }
    }

    public var availability: IngredientAvailability {
        get { ingredientAvailabilityRaw.flatMap(IngredientAvailability.init(rawValue:)) ?? .everywhere }
        set { ingredientAvailabilityRaw = newValue.rawValue }
    }

    public var store: GroceryStore {
        get { storeRaw.flatMap(GroceryStore.init(rawValue:)) ?? .generic }
        set { storeRaw = newValue.rawValue }
    }

    /// Nom du magasin transmis à l'IA ; « Autre » → nom saisi.
    public var storeName: String {
        if store == .other, let name = customStoreName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return store == .other ? GroceryStore.generic.displayName : store.displayName
    }

    public var promptPreferences: PromptPreferences {
        PromptPreferences(
            mealsPerDay: mealsPerDay, maxPrepMinutes: maxPrepMinutes, weeklyBudgetEur: weeklyBudget,
            budgetTolerance: tolerance, allergies: allergyList, dislikedFoods: excludedFoods, likedFoods: likedFoods,
            equipment: equipment, batchCooking: batchCooking, ingredientAvailability: availability, store: storeName,
            ownedSupplements: supplementList, trainingTime: trainingTimeLabel
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
