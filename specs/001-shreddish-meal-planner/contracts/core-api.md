# Contrat : API publique ShreddishCore

Package Swift pur (Foundation seulement). Fonctions déterministes, testées d'abord
(constitution V). Signatures indicatives.

## Nutrition

```swift
public struct ProfileInput: Sendable {
    sex: Sex; age: Int; heightCm: Double; weightKg: Double
    activity: ActivityLevel; goal: Goal
    proteinPerKg: Double?; fatPerKg: Double?; calorieAdjustment: Double?
}

public enum ProfileValidationError: Error { ageOutOfRange, heightOutOfRange, weightOutOfRange, overrideOutOfRange(field: String) }

public enum NutritionCalculator {
    static func validate(_ input: ProfileInput) throws(ProfileValidationError)
    static func bmr(_ input: ProfileInput) -> Double
    static func tdee(_ input: ProfileInput) -> Double
    static func targets(for input: ProfileInput) throws(ProfileValidationError) -> NutritionTargets
}
```

Valeurs de référence (tests) :
- Homme, 30 ans, 180 cm, 80 kg, modéré, sèche : BMR 1780, TDEE 2759, cible 2207 kcal,
  P 160 g, L 64 g, G 248 g.
- Femme, 25 ans, 165 cm, 60 kg, sédentaire, sèche : BMR 1345, TDEE 1614, cible 1291 → plancher
  1345 (BMR) appliqué, `floorApplied = true`.

## Validation IA

```swift
public struct GenerationConstraints: Sendable { targets; mealsPerDay; maxPrepMinutes; dailyBudgetEUR; batchCooking: Bool; excludedFoods: [String] }

public enum AIOutputValidator {
    static func validate(week: WeekPlanDTO, constraints: GenerationConstraints) -> ValidationResult
    static func validate(day: DayPlanDTO, constraints: GenerationConstraints) -> ValidationResult
    static func validate(meal: MealDTO, constraints: GenerationConstraints) -> ValidationResult
}

public struct ValidationResult: Sendable {
    let fatal: [ValidationIssue]      // rejet + retry
    let corrected: [ValidationIssue]  // kcal recalculé depuis macros, unités normalisées
    let warnings: [ValidationIssue]   // jour > 10 % de la cible, coût jour > 110 % du budget
    let sanitized: <DTO>?             // version corrigée, nil si fatal
}
```

## Totaux et bilans

```swift
public enum Totals {
    static func planned(_ meals: [MealDTO]) -> MacroTotals
    static func actual(meals: [MealDTO], statuses: [MealStatus], extras: [ExtraDTO]) -> MacroTotals
    static func deviation(_ totals: MacroTotals, target: NutritionTargets) -> Double  // ratio signé
    static func weeklySummary(days: [DayLogDTO], now: Date) -> WeeklySummary
}
```

## Courses

```swift
public enum ShoppingListBuilder {
    static func normalize(_ name: String) -> String   // minuscules, sans accents, trim, singulier simple
    static func build(from days: [DayPlanDTO]) -> [ShoppingLine]  // trié par rayon puis nom
}
```

## Poids

```swift
public enum WeightTrend {
    static func weeklyLossRate(_ entries: [WeightEntryDTO]) -> Double?  // % / semaine, nil si < 2 sem.
    static func isTooFast(_ entries: [WeightEntryDTO], goal: Goal) -> Bool  // > 1 % en sèche
}
```

## Prompt

```swift
public enum PromptBuilder {
    static func systemInstructions() -> String
    static func weekInput(targets:, goal:, preferences:) -> String       // JSON
    static func dayInput(...) -> String
    static func replaceMealInput(...) -> String
}
```

Testé : aucune donnée hors liste FR-021 dans l'input (pas d'âge, poids, sexe, nom).
