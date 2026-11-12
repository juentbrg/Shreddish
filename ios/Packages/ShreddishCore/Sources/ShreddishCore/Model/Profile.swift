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
    // Spec 002 (SchemaV2), optionnels pour la migration légère depuis V1.
    /// `DailyActivity` ; `nil` : ancien `activity` utilisé (FR-104).
    public var dailyActivityRaw: String?
    public var trainingSessionsPerWeek: Int?
    public var trainingMinutes: Int?
    public var trainingIntensityRaw: String?
    /// Ajustement de calibration par les pesées, en kcal.
    public var tdeeAdjustmentKcal: Double?
    public var lastCalibrationAt: Date?
    /// `nil` = actif (FR-109).
    public var autoCalibrate: Bool?

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

    public var dailyActivity: DailyActivity? {
        get { dailyActivityRaw.flatMap(DailyActivity.init(rawValue:)) }
        set { dailyActivityRaw = newValue?.rawValue }
    }

    public var training: TrainingLoad? {
        get {
            guard let sessions = trainingSessionsPerWeek, let minutes = trainingMinutes,
                  let intensity = trainingIntensityRaw.flatMap(TrainingIntensity.init(rawValue:)) else { return nil }
            return TrainingLoad(sessionsPerWeek: sessions, minutesPerSession: minutes, intensity: intensity)
        }
        set {
            trainingSessionsPerWeek = newValue?.sessionsPerWeek
            trainingMinutes = newValue?.minutesPerSession
            trainingIntensityRaw = newValue?.intensity.rawValue
        }
    }

    public var isAutoCalibrationOn: Bool {
        get { autoCalibrate ?? true }
        set { autoCalibrate = newValue }
    }

    public func age(on date: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.year], from: birthDate, to: date).year ?? 0
    }

    public func input(clock: any AppClock) -> ProfileInput {
        ProfileInput(
            sex: sex, age: age(on: clock.now, calendar: clock.calendar), heightCm: heightCm, weightKg: weightKg,
            activity: activity, goal: goal, proteinPerKg: proteinPerKg, fatPerKg: fatPerKg,
            calorieAdjustment: calorieAdjustment, dailyActivity: dailyActivity, training: training,
            tdeeAdjustmentKcal: tdeeAdjustmentKcal ?? 0
        )
    }

    public func targets(clock: any AppClock) -> NutritionTargets? {
        try? NutritionCalculator.targets(for: input(clock: clock))
    }
}
