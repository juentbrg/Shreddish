import Testing
@testable import ShreddishCore

struct NutritionValidationTests {
    static let valid = ProfileInput(
        sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate, goal: .cut
    )

    @Test func validProfilePasses() throws {
        try NutritionCalculator.validate(Self.valid)
    }

    @Test(arguments: [15, 91])
    func ageOutOfRange(age: Int) {
        var input = Self.valid
        input.age = age
        #expect(throws: ProfileValidationError.ageOutOfRange) { try NutritionCalculator.validate(input) }
    }

    @Test(arguments: [16, 90])
    func ageBoundsAccepted(age: Int) throws {
        var input = Self.valid
        input.age = age
        try NutritionCalculator.validate(input)
    }

    @Test(arguments: [30.0, 119.9, 230.1])
    func heightOutOfRange(height: Double) {
        var input = Self.valid
        input.heightCm = height
        #expect(throws: ProfileValidationError.heightOutOfRange) { try NutritionCalculator.validate(input) }
    }

    @Test(arguments: [34.9, 250.1])
    func weightOutOfRange(weight: Double) {
        var input = Self.valid
        input.weightKg = weight
        #expect(throws: ProfileValidationError.weightOutOfRange) { try NutritionCalculator.validate(input) }
    }

    @Test(arguments: [1.1, 3.1])
    func proteinOverrideOutOfRange(value: Double) {
        var input = Self.valid
        input.proteinPerKg = value
        #expect(throws: ProfileValidationError.overrideOutOfRange(.proteinPerKg)) {
            try NutritionCalculator.validate(input)
        }
    }

    @Test(arguments: [0.5, 1.6])
    func fatOverrideOutOfRange(value: Double) {
        var input = Self.valid
        input.fatPerKg = value
        #expect(throws: ProfileValidationError.overrideOutOfRange(.fatPerKg)) {
            try NutritionCalculator.validate(input)
        }
    }

    @Test(arguments: [-0.31, 0.21])
    func adjustmentOverrideOutOfRange(value: Double) {
        var input = Self.valid
        input.calorieAdjustment = value
        #expect(throws: ProfileValidationError.overrideOutOfRange(.calorieAdjustment)) {
            try NutritionCalculator.validate(input)
        }
    }

    @Test func overrideBoundsAccepted() throws {
        var input = Self.valid
        input.proteinPerKg = 1.2
        input.fatPerKg = 0.6
        input.calorieAdjustment = -0.30
        try NutritionCalculator.validate(input)
        input.proteinPerKg = 3.0
        input.fatPerKg = 1.5
        input.calorieAdjustment = 0.20
        try NutritionCalculator.validate(input)
    }
}
