import Foundation

/// Données de profil nécessaires au calcul des cibles.
public struct ProfileInput: Sendable, Equatable {
    public var sex: Sex
    public var age: Int
    public var heightCm: Double
    public var weightKg: Double
    public var activity: ActivityLevel
    public var goal: Goal
    public var proteinPerKg: Double?
    public var fatPerKg: Double?
    public var calorieAdjustment: Double?

    public init(
        sex: Sex, age: Int, heightCm: Double, weightKg: Double, activity: ActivityLevel, goal: Goal,
        proteinPerKg: Double? = nil, fatPerKg: Double? = nil, calorieAdjustment: Double? = nil
    ) {
        self.sex = sex
        self.age = age
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activity = activity
        self.goal = goal
        self.proteinPerKg = proteinPerKg
        self.fatPerKg = fatPerKg
        self.calorieAdjustment = calorieAdjustment
    }
}

public enum ProfileValidationError: Error, Equatable, Sendable {
    public enum Field: String, Sendable {
        case proteinPerKg
        case fatPerKg
        case calorieAdjustment
    }

    case ageOutOfRange
    case heightOutOfRange
    case weightOutOfRange
    case overrideOutOfRange(Field)
}

/// Calcul déterministe des cibles (constitution II, research R7). Jamais délégué à l'IA.
public enum NutritionCalculator {
    public static let ageRange = 16...90
    public static let heightRange = 120.0...230.0
    public static let weightRange = 35.0...250.0
    public static let proteinPerKgRange = 1.2...3.0
    public static let fatPerKgRange = 0.6...1.5
    public static let calorieAdjustmentRange = -0.30...0.20

    /// Lipides par défaut et plancher absolu, en g/kg (FR-003).
    public static let defaultFatPerKg = 0.8
    public static let minimumFatPerKg = 0.6

    public static func validate(_ input: ProfileInput) throws(ProfileValidationError) {
        guard ageRange.contains(input.age) else { throw .ageOutOfRange }
        guard heightRange.contains(input.heightCm) else { throw .heightOutOfRange }
        guard weightRange.contains(input.weightKg) else { throw .weightOutOfRange }
        if let value = input.proteinPerKg, !proteinPerKgRange.contains(value) {
            throw .overrideOutOfRange(.proteinPerKg)
        }
        if let value = input.fatPerKg, !fatPerKgRange.contains(value) {
            throw .overrideOutOfRange(.fatPerKg)
        }
        if let value = input.calorieAdjustment, !calorieAdjustmentRange.contains(value) {
            throw .overrideOutOfRange(.calorieAdjustment)
        }
    }

    /// Métabolisme de base, Mifflin-St Jeor.
    public static func bmr(_ input: ProfileInput) -> Double {
        let sexConstant: Double = input.sex == .male ? 5 : -161
        return 10 * input.weightKg + 6.25 * input.heightCm - 5 * Double(input.age) + sexConstant
    }

    /// Dépense journalière totale.
    public static func tdee(_ input: ProfileInput) -> Double {
        bmr(input) * input.activity.factor
    }

    /// Plancher calorique : 1500 kcal homme, 1200 kcal femme ; en sèche, jamais sous le BMR.
    public static func floorKcal(_ input: ProfileInput) -> Double {
        let base: Double = input.sex == .male ? 1500 : 1200
        return input.goal == .cut ? max(base, bmr(input)) : base
    }

    public static func targets(for input: ProfileInput) throws(ProfileValidationError) -> NutritionTargets {
        try validate(input)

        let bmr = bmr(input)
        let tdee = tdee(input)
        let adjustment = input.calorieAdjustment ?? input.goal.defaultCalorieAdjustment
        let adjusted = tdee * (1 + adjustment)
        let floor = floorKcal(input)
        let floorApplied = adjusted < floor
        let kcal = max(adjusted, floor)

        var warnings: [TargetWarning] = floorApplied ? [.floorApplied] : []

        let proteinPerKg = input.proteinPerKg ?? input.goal.defaultProteinPerKg
        let protein = input.weightKg * proteinPerKg
        let fatPerKg = input.fatPerKg ?? defaultFatPerKg
        var fat = input.weightKg * fatPerKg
        var carbsKcal = kcal - 4 * protein - 9 * fat

        if carbsKcal < 0 {
            // Lipides abaissés juste assez pour des glucides à 0, sans passer sous 0,6 g/kg.
            let minimumFat = input.weightKg * minimumFatPerKg
            let fatForZeroCarbs = (kcal - 4 * protein) / 9
            let reduced = max(minimumFat, fatForZeroCarbs)
            if reduced < fat {
                fat = reduced
                warnings.append(.fatReduced)
            }
            carbsKcal = kcal - 4 * protein - 9 * fat
            if carbsKcal < 0 {
                carbsKcal = 0
                warnings.append(.carbsAtZero)
            }
        }

        return NutritionTargets(
            bmr: Int(bmr.rounded()),
            tdee: Int(tdee.rounded()),
            targetKcal: Int(kcal.rounded()),
            proteinG: Int(protein.rounded()),
            carbsG: Int((carbsKcal / 4).rounded()),
            fatG: Int(fat.rounded()),
            floorApplied: floorApplied,
            warnings: warnings,
            breakdown: CalculationBreakdown(
                bmr: bmr,
                activityFactor: input.activity.factor,
                tdee: tdee,
                calorieAdjustment: adjustment,
                adjustedKcal: kcal,
                floorKcal: floor,
                proteinPerKg: proteinPerKg,
                fatPerKg: fat / input.weightKg
            )
        )
    }
}
