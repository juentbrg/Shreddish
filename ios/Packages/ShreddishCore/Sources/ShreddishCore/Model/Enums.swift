import Foundation

// Raw values snake_case : identiques à contracts/ai-meal.schema.json et au JSON envoyé à l'IA.

public enum Sex: String, Codable, Sendable, CaseIterable {
    case male
    case female
}

public enum ActivityLevel: String, Codable, Sendable, CaseIterable {
    case sedentary
    case light
    case moderate
    case active
    case veryActive = "very_active"

    /// Facteur multiplicateur du métabolisme de base (research R7).
    public var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }
}

public enum Goal: String, Codable, Sendable, CaseIterable {
    case cut
    case bulk
    case recomp

    /// Ajustement calorique par défaut appliqué à la dépense totale (FR-003).
    public var defaultCalorieAdjustment: Double {
        switch self {
        case .cut: -0.20
        case .bulk: 0.10
        case .recomp: 0
        }
    }

    /// Protéines par défaut en g par kg de poids (FR-003).
    public var defaultProteinPerKg: Double {
        switch self {
        case .cut, .recomp: 2.0
        case .bulk: 1.8
        }
    }
}

public enum MealType: String, Codable, Sendable, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snack

    /// Ordre d'affichage dans une journée.
    public var sortIndex: Int {
        switch self {
        case .breakfast: 0
        case .lunch: 1
        case .snack: 2
        case .dinner: 3
        }
    }
}

public enum Aisle: String, Codable, Sendable, CaseIterable {
    case fruitsLegumes = "fruits_legumes"
    case viandePoisson = "viande_poisson"
    case cremerie
    case epicerie
    case surgeles
    case boulangerie
    case autre

    /// Ordre de parcours en magasin pour la liste de courses.
    public var sortIndex: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }
}

/// Unité de quantité normalisée (research R11). Nommée `MeasureUnit` : `Unit` existe dans Foundation.
public enum MeasureUnit: String, Codable, Sendable, CaseIterable {
    case g
    case ml
    case piece
}

public enum MealStatus: String, Codable, Sendable, CaseIterable {
    case planned
    case eaten
    case skipped
}
