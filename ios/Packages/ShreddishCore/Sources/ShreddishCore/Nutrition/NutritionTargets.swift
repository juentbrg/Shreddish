import Foundation

/// Kcal et macros d'un repas, d'une journée ou d'une cible.
public struct MacroTotals: Codable, Sendable, Equatable {
    public var kcal: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double

    public init(kcal: Double, proteinG: Double, carbsG: Double, fatG: Double) {
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }

    public static let zero = MacroTotals(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0)

    /// Kcal recalculées depuis les macros (4 / 4 / 9).
    public var kcalFromMacros: Double { 4 * proteinG + 4 * carbsG + 9 * fatG }

    public static func + (lhs: MacroTotals, rhs: MacroTotals) -> MacroTotals {
        MacroTotals(
            kcal: lhs.kcal + rhs.kcal,
            proteinG: lhs.proteinG + rhs.proteinG,
            carbsG: lhs.carbsG + rhs.carbsG,
            fatG: lhs.fatG + rhs.fatG
        )
    }

    public static func - (lhs: MacroTotals, rhs: MacroTotals) -> MacroTotals {
        MacroTotals(
            kcal: lhs.kcal - rhs.kcal,
            proteinG: lhs.proteinG - rhs.proteinG,
            carbsG: lhs.carbsG - rhs.carbsG,
            fatG: lhs.fatG - rhs.fatG
        )
    }

    /// Valeurs arrondies à l'unité.
    public var rounded: MacroTotals {
        MacroTotals(
            kcal: kcal.rounded(), proteinG: proteinG.rounded(),
            carbsG: carbsG.rounded(), fatG: fatG.rounded()
        )
    }
}

extension Sequence where Element == MacroTotals {
    public func sum() -> MacroTotals { reduce(.zero, +) }
}

public enum TargetWarning: String, Codable, Sendable, Equatable {
    /// Cible ramenée au plancher de sécurité (FR-004).
    case floorApplied = "floor_applied"
    /// Lipides abaissés sous 0,8 g/kg (jusqu'à 0,6) pour garder des glucides ≥ 0 (FR-003).
    case fatReduced = "fat_reduced"
    /// Glucides à 0 : protéines + lipides minimum dépassent déjà la cible.
    case carbsAtZero = "carbs_at_zero"
}

/// Étapes du calcul, affichées à l'utilisateur (FR-005). Valeurs non arrondies.
public struct CalculationBreakdown: Codable, Sendable, Equatable {
    public var bmr: Double
    public var activityFactor: Double
    public var tdee: Double
    public var calorieAdjustment: Double
    public var adjustedKcal: Double
    public var floorKcal: Double
    public var proteinPerKg: Double
    public var fatPerKg: Double
}

/// Cibles quotidiennes dérivées du profil, arrondies à l'unité en fin de calcul.
public struct NutritionTargets: Codable, Sendable, Equatable {
    public var bmr: Int
    public var tdee: Int
    public var targetKcal: Int
    public var proteinG: Int
    public var carbsG: Int
    public var fatG: Int
    public var floorApplied: Bool
    public var warnings: [TargetWarning]
    public var breakdown: CalculationBreakdown

    public var macros: MacroTotals {
        MacroTotals(
            kcal: Double(targetKcal), proteinG: Double(proteinG),
            carbsG: Double(carbsG), fatG: Double(fatG)
        )
    }
}
