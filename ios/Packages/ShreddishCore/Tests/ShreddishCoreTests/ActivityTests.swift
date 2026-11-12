import Foundation
import Testing
@testable import ShreddishCore

struct ActivityTests {
    /// Homme 30 ans, 180 cm, 80 kg, bureau, 3 × muscu à l'échec + 2 × escalade de 75 min, sèche.
    static let detailed = ProfileInput(
        sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate, goal: .cut,
        dailyActivity: .sedentary,
        training: TrainingLoad(sessionsPerWeek: 5, minutesPerSession: 75, intensity: .intense)
    )

    @Test func kcalPerSessionUsesNetMet() {
        let load = TrainingLoad(sessionsPerWeek: 5, minutesPerSession: 75, intensity: .intense)
        #expect(abs(load.kcalPerSession(weightKg: 80) - 550) < 0.001) // (6,5 − 1) × 80 × 1,25
        #expect(abs(load.kcalPerDay(weightKg: 80) - 2750.0 / 7) < 0.001)
    }

    @Test func referenceDetailedProfile() throws {
        let targets = try NutritionCalculator.targets(for: Self.detailed)
        #expect(targets.tdee == 2529)       // 1780 × 1,2 + 392,9
        #expect(targets.targetKcal == 2023) // × 0,8
        #expect(targets.proteinG == 160)
        #expect(targets.fatG == 64)
        #expect(targets.carbsG == 202)
        #expect(targets.breakdown.dailyActivityFactor == 1.2)
        #expect(abs((targets.breakdown.exerciseKcalPerDay ?? 0) - 392.857) < 0.01)
    }

    @Test func onboardingDefaults() throws {
        var input = Self.detailed
        input.training = .defaultLoad
        let targets = try NutritionCalculator.targets(for: input)
        #expect(targets.tdee == 2273)
        #expect(targets.targetKcal == 1819)
    }

    @Test func noSessionMeansDailyFactorOnly() throws {
        var input = Self.detailed
        input.dailyActivity = .veryActive
        input.training = TrainingLoad(sessionsPerWeek: 0, minutesPerSession: 60, intensity: .moderate)
        let targets = try NutritionCalculator.targets(for: input)
        #expect(targets.tdee == 2670) // 1780 × 1,5
    }

    @Test func legacyProfileKeepsActivityLevel() throws {
        var input = Self.detailed
        input.dailyActivity = nil
        input.training = nil
        let targets = try NutritionCalculator.targets(for: input)
        #expect(targets.tdee == 2759)
        #expect(targets.breakdown.exerciseKcalPerDay == nil)
    }

    @Test func calibrationAdjustmentAddsToTdee() throws {
        var input = Self.detailed
        input.training = .defaultLoad
        input.tdeeAdjustmentKcal = 100
        let targets = try NutritionCalculator.targets(for: input)
        #expect(targets.tdee == 2373)
        #expect(targets.targetKcal == 1899)
        #expect(targets.breakdown.calibrationKcal == 100)
    }

    @Test func calibrationAdjustmentIsClamped() throws {
        var input = Self.detailed
        input.tdeeAdjustmentKcal = 2000
        let targets = try NutritionCalculator.targets(for: input)
        #expect(targets.tdee == 3129) // 2529 + 600
    }

    @Test(arguments: [-1, 15])
    func sessionsOutOfRange(sessions: Int) {
        var input = Self.detailed
        input.training = TrainingLoad(sessionsPerWeek: sessions, minutesPerSession: 60, intensity: .moderate)
        #expect(throws: ProfileValidationError.trainingOutOfRange) { try NutritionCalculator.validate(input) }
    }

    @Test(arguments: [10, 241])
    func minutesOutOfRange(minutes: Int) {
        var input = Self.detailed
        input.training = TrainingLoad(sessionsPerWeek: 3, minutesPerSession: minutes, intensity: .moderate)
        #expect(throws: ProfileValidationError.trainingOutOfRange) { try NutritionCalculator.validate(input) }
    }

    @Test func oldTargetsSnapshotStillDecodes() throws {
        // Cibles enregistrées par la v1 dans un planning, sans les nouveaux champs du détail.
        let json = """
        {"bmr":1780,"tdee":2759,"targetKcal":2207,"proteinG":160,"carbsG":248,"fatG":64,"floorApplied":false,
         "warnings":[],"breakdown":{"bmr":1780,"activityFactor":1.55,"tdee":2759,"calorieAdjustment":-0.2,
         "adjustedKcal":2207.2,"floorKcal":1780,"proteinPerKg":2,"fatPerKg":0.8}}
        """
        let targets = try JSONDecoder().decode(NutritionTargets.self, from: Data(json.utf8))
        #expect(targets.targetKcal == 2207)
        #expect(targets.breakdown.exerciseKcalPerDay == nil)
    }
}
