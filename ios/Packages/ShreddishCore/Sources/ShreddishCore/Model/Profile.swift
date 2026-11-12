import Foundation
import SwiftData

/// Profil unique de l'utilisateur (data-model.md). Enums stockés en raw values.
@Model
public final class Profile {
    public var sexRaw: String
    /// Âge dérivé de la date de naissance : jamais périmé.
    public var birthDate: Date
    public var heightCm: Double
    /// Poids courant ; mis à jour par la dernière pesée acceptée (FR-017).
    public var weightKg: Double
    public var activityRaw: String
    public var goalRaw: String
    public var proteinPerKg: Double?
    public var fatPerKg: Double?
    public var calorieAdjustment: Double?
    public var disclaimerAcceptedAt: Date?

    public init(
        sex: Sex, birthDate: Date, heightCm: Double, weightKg: Double, activity: ActivityLevel, goal: Goal
    ) {
        sexRaw = sex.rawValue
        self.birthDate = birthDate
        self.heightCm = heightCm
        self.weightKg = weightKg
        activityRaw = activity.rawValue
        goalRaw = goal.rawValue
    }

    public var sex: Sex {
        get { Sex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }

    public var activity: ActivityLevel {
        get { ActivityLevel(rawValue: activityRaw) ?? .moderate }
        set { activityRaw = newValue.rawValue }
    }

    public var goal: Goal {
        get { Goal(rawValue: goalRaw) ?? .cut }
        set { goalRaw = newValue.rawValue }
    }

    public func age(on date: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.year], from: birthDate, to: date).year ?? 0
    }

    public func input(clock: any AppClock) -> ProfileInput {
        ProfileInput(
            sex: sex, age: age(on: clock.now, calendar: clock.calendar), heightCm: heightCm, weightKg: weightKg,
            activity: activity, goal: goal, proteinPerKg: proteinPerKg, fatPerKg: fatPerKg,
            calorieAdjustment: calorieAdjustment
        )
    }

    public func targets(clock: any AppClock) -> NutritionTargets? {
        try? NutritionCalculator.targets(for: input(clock: clock))
    }
}
