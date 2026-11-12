import Testing
@testable import ShreddishCore

struct NutritionCalculatorTests {
    // Valeurs de référence : contracts/core-api.md.
    static let man = ProfileInput(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate, goal: .cut)
    static let woman = ProfileInput(sex: .female, age: 25, heightCm: 165, weightKg: 60, activity: .sedentary, goal: .cut)

    @Test func referenceManCut() throws {
        let targets = try NutritionCalculator.targets(for: Self.man)
        #expect(targets.bmr == 1780)
        #expect(targets.tdee == 2759)
        #expect(targets.targetKcal == 2207)
        #expect(targets.proteinG == 160)
        #expect(targets.fatG == 64)
        #expect(targets.carbsG == 248)
        #expect(targets.floorApplied == false)
        #expect(targets.warnings.isEmpty)
    }

    @Test func referenceWomanCutHitsBmrFloor() throws {
        let targets = try NutritionCalculator.targets(for: Self.woman)
        #expect(targets.bmr == 1345)
        #expect(targets.tdee == 1614)
        #expect(targets.targetKcal == 1345)
        #expect(targets.floorApplied)
        #expect(targets.warnings.contains(.floorApplied))
    }

    @Test func bmrFormula() {
        #expect(abs(NutritionCalculator.bmr(Self.man) - 1780) < 0.001)
        #expect(abs(NutritionCalculator.bmr(Self.woman) - 1345.25) < 0.001)
    }

    @Test func bulkUsesPlusTenPercentAnd18Protein() throws {
        var input = Self.man
        input.goal = .bulk
        let targets = try NutritionCalculator.targets(for: input)
        #expect(targets.targetKcal == 3035) // 2759 × 1,10 = 3034,9
        #expect(targets.proteinG == 144)    // 80 × 1,8
        #expect(targets.fatG == 64)
    }

    @Test func recompKeepsMaintenance() throws {
        var input = Self.man
        input.goal = .recomp
        let targets = try NutritionCalculator.targets(for: input)
        #expect(targets.targetKcal == 2759)
        #expect(targets.proteinG == 160)
    }

    @Test func overridesApplied() throws {
        var input = Self.man
        input.proteinPerKg = 2.2
        input.fatPerKg = 1.0
        input.calorieAdjustment = -0.25
        let targets = try NutritionCalculator.targets(for: input)
        #expect(targets.targetKcal == 2069) // 2759 × 0,75 = 2069,25
        #expect(targets.proteinG == 176)
        #expect(targets.fatG == 80)
        #expect(targets.carbsG == 161)      // (2069,25 − 704 − 720) / 4 = 161,3
    }

    @Test func maleFloorIs1500WhenNotCutting() throws {
        let input = ProfileInput(
            sex: .male, age: 90, heightCm: 120, weightKg: 35, activity: .sedentary, goal: .recomp
        )
        let targets = try NutritionCalculator.targets(for: input)
        #expect(targets.targetKcal == 1500)
        #expect(targets.floorApplied)
    }

    @Test func femaleFloorIs1200WhenNotCutting() throws {
        let input = ProfileInput(
            sex: .female, age: 90, heightCm: 120, weightKg: 35, activity: .sedentary, goal: .recomp
        )
        let targets = try NutritionCalculator.targets(for: input)
        #expect(targets.targetKcal == 1200)
        #expect(targets.floorApplied)
    }

    @Test func fatReducedDownTo06WhenCarbsWouldBeNegative() throws {
        // Lourd, sédentaire, sèche agressive, protéines hautes : glucides négatifs à 0,8 g/kg de lipides.
        let input = ProfileInput(
            sex: .female, age: 60, heightCm: 150, weightKg: 140, activity: .sedentary, goal: .cut,
            proteinPerKg: 3.0, fatPerKg: nil, calorieAdjustment: -0.30
        )
        let targets = try NutritionCalculator.targets(for: input)
        #expect(targets.warnings.contains(.fatReduced))
        #expect(Double(targets.fatG) >= 0.6 * 140 - 0.5)
        #expect(Double(targets.fatG) < 0.8 * 140)
        #expect(targets.carbsG >= 0)
    }

    @Test func fatNeverBelow06AndCarbsClampedToZero() throws {
        let input = ProfileInput(
            sex: .female, age: 90, heightCm: 120, weightKg: 250, activity: .sedentary, goal: .cut,
            proteinPerKg: 3.0, fatPerKg: nil, calorieAdjustment: -0.30
        )
        let targets = try NutritionCalculator.targets(for: input)
        #expect(targets.fatG == 150) // 0,6 × 250
        #expect(targets.carbsG == 0)
        #expect(targets.warnings.contains(.carbsAtZero))
    }

    @Test func roundingHappensAtTheEnd() throws {
        let targets = try NutritionCalculator.targets(for: Self.man)
        // Glucides calculés sur 2207,2 kcal non arrondies : (2207,2 − 640 − 576) / 4 = 247,8.
        #expect(targets.breakdown.adjustedKcal > 2207.1)
        #expect(targets.carbsG == 248)
    }

    @Test func invalidProfileThrows() {
        var input = Self.man
        input.heightCm = 30
        #expect(throws: ProfileValidationError.heightOutOfRange) { try NutritionCalculator.targets(for: input) }
    }
}
