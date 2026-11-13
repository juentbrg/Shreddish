import Foundation
import Testing
@testable import ShreddishCore

/// Spec 010 : macros Ciqual, ajustement des portions, garde-fous, placement des compléments.
struct NutritionPipelineTests {
    /// Œufs : ambigu (oie, cane) tranché comme le ferait l'IA.
    let cache = InMemoryFoodMatchCache([NutritionResolver.key("Œufs"): 22000])
    var resolver: NutritionResolver { NutritionResolver(cache: cache) }

    func chicken(_ grams: Double = 150) -> IngredientDTO {
        IngredientDTO(name: "Blanc de poulet", quantity: grams, unit: "g", aisle: .viandePoisson, costEur: 1.8, unitPriceEur: 12)
    }

    func rice(_ grams: Double = 80) -> IngredientDTO {
        IngredientDTO(name: "Riz thaï ou basmati cru", quantity: grams, unit: "g", aisle: .epicerie, costEur: 0.2, unitPriceEur: 2.5)
    }

    func oil(_ ml: Double = 10) -> IngredientDTO {
        IngredientDTO(name: "Huile de colza", quantity: ml, unit: "ml", aisle: .epicerie, costEur: 0.03, unitPriceEur: 3)
    }

    func eggs(_ count: Double = 2) -> IngredientDTO {
        IngredientDTO(name: "Œufs", quantity: count, unit: "piece", aisle: .cremerie, costEur: 0.6, unitPriceEur: 0.3, pieceG: 60)
    }

    // MARK: Résolution

    @Test func mealMacrosComeFromCiqual() {
        let draft = meal(kcal: 552, protein: 40, carbs: 62, fat: 16, ingredients: [chicken(), rice(), oil(), eggs()])
        #expect(resolver.questions(for: [draft]).isEmpty)
        let (resolved, verified) = resolver.resolve(draft)
        #expect(verified)
        #expect(resolved.ingredients.allSatisfy { $0.foodCode != nil })
        // ≈ 150 g poulet (≈ 33 g P) + 80 g riz (≈ 6 g P) + 2 œufs (≈ 15 g P).
        #expect((45...65).contains(resolved.proteinG))
        #expect(resolved.kcal != 552)
    }

    @Test func pieceWithoutWeightKeepsDeclaredMacros() {
        var egg = eggs()
        egg.pieceG = nil
        let (resolved, verified) = resolver.resolve(meal(kcal: 500, ingredients: [egg]))
        #expect(!verified)
        #expect(resolved.kcal == 500)
    }

    @Test func ambiguousIngredientIsAskedOnceThenCached() throws {
        let banana = IngredientDTO(name: "Banane", quantity: 120, unit: "g", aisle: .fruitsLegumes, costEur: 0.3)
        let questions = resolver.questions(for: [meal(ingredients: [banana]), meal(ingredients: [banana])])
        #expect(questions.count == 1)
        let chosen = try #require(questions.first?.candidates.first { $0.name.hasPrefix("Banane, chair") })
        resolver.record([FoodChoice(index: 0, code: chosen.code)], for: questions)
        #expect(resolver.questions(for: [meal(ingredients: [banana])]).isEmpty)
        #expect(resolver.resolve(meal(ingredients: [banana])).meal.ingredients.first?.foodCode == chosen.code)
    }

    @Test func choiceOutsideCandidatesIsIgnored() throws {
        let banana = IngredientDTO(name: "Banane", quantity: 120, unit: "g", aisle: .fruitsLegumes, costEur: 0.3)
        let questions = resolver.questions(for: [meal(ingredients: [banana])])
        resolver.record([FoodChoice(index: 0, code: 1)], for: questions)
        #expect(cache.code(for: NutritionResolver.key("Banane")) == .some(nil))
    }

    @Test func ownedSupplementUsesEnteredValues() {
        let whey = OwnedSupplement(
            name: "Whey",
            info: SupplementInfo(servingG: 30, kcalPerServing: 118, proteinPerServingG: 24, carbsPerServingG: 2, fatPerServingG: 1.5)
        )
        let resolver = NutritionResolver(cache: cache, supplements: [whey])
        let scoop = IngredientDTO(name: "Whey", quantity: 30, unit: "g", aisle: .autre, costEur: 0)
        let (resolved, verified) = resolver.resolve(meal(.snack, ingredients: [scoop]))
        #expect(verified)
        #expect(resolved.proteinG == 24)
        #expect(resolved.kcal == 118)
    }

    // MARK: Ajustement

    @Test func portionsAreScaledTowardTargets() {
        let meals = [
            meal(.breakfast, ingredients: [eggs(), rice(60)]),
            meal(.lunch, ingredients: [chicken(120), rice(70), oil(8)]),
            meal(.dinner, ingredients: [chicken(120), rice(70), oil(8)]),
            meal(.snack, ingredients: [rice(40)]),
        ].map { resolver.resolve($0).meal }
        let before = Totals.planned(meals)
        let adjusted = PortionAdjuster.adjust(meals, to: referenceTargets, resolver: resolver)
        let after = Totals.planned(adjusted)
        #expect(abs(after.proteinG - referenceTargets.proteinG) < abs(before.proteinG - referenceTargets.proteinG))
        #expect(abs(after.carbsG - referenceTargets.carbsG) < abs(before.carbsG - referenceTargets.carbsG))
        #expect(adjusted[0].ingredients[0].quantity == 2, "pièces fixes")
        #expect(adjusted.flatMap(\.ingredients).allSatisfy { $0.quantity.truncatingRemainder(dividingBy: 1) == 0 })
    }

    @Test func unansweredAmbiguityUsesBestCandidateWithoutCaching() {
        let banana = IngredientDTO(name: "Banane", quantity: 120, unit: "g", aisle: .fruitsLegumes, costEur: 0.3)
        _ = resolver.questions(for: [meal(ingredients: [banana])])
        let (resolved, verified) = resolver.resolve(meal(ingredients: [banana]))
        #expect(verified)
        #expect(resolved.ingredients.first?.foodCode != nil)
        #expect(cache.code(for: NutritionResolver.key("Banane")) == nil)
    }

    @Test func factorsStayWithinBounds() {
        let tiny = [resolver.resolve(meal(ingredients: [chicken(20), rice(20)])).meal]
        let adjusted = PortionAdjuster.adjust(tiny, to: referenceTargets, resolver: resolver)
        #expect(adjusted[0].ingredients[0].quantity <= 20 * PortionAdjuster.factorRange.upperBound + 5)
    }

    @Test func adjustedCostFollowsQuantities() {
        let meals = [resolver.resolve(meal(ingredients: [chicken(100), rice(50)])).meal]
        let adjusted = PortionAdjuster.adjust(meals, to: referenceTargets, resolver: resolver)
        let chickenLine = adjusted[0].ingredients[0]
        #expect(abs(chickenLine.costEur - BudgetMath.cents(chickenLine.quantity * 12 / 1000)) < 0.001)
    }

    // MARK: Garde-fous

    @Test func absurdPieceCountIsFatal() {
        var egg = eggs(150)
        egg.unitPriceEur = 4.5
        let result = AIOutputValidator.validate(meal: meal(ingredients: [egg]), constraints: constraints())
        #expect(result.fatal.contains(.implausibleQuantity(ingredient: "Œufs")))
    }

    @Test func absurdPriceIsFatal() {
        var line = chicken()
        line.unitPriceEur = 450
        let result = AIOutputValidator.validate(meal: meal(ingredients: [line]), constraints: constraints())
        #expect(result.fatal.contains(.implausiblePrice(ingredient: "Blanc de poulet")))
    }

    @Test func repetitiveWeekIsFatal() {
        let days = (0...6).map { offset in
            DayPlanDTO(dayOffset: offset, meals: [
                meal(.breakfast, name: "Porridge \(offset)"), meal(.lunch, name: "Poulet riz"),
                meal(.dinner, name: "Omelette \(offset)"), meal(.snack, name: "Shake"),
            ])
        }
        let result = AIOutputValidator.validate(week: WeekPlanDTO(prepSessions: [], days: days), constraints: constraints())
        #expect(result.fatal.contains(.repetitiveMeal(name: "poulet riz", count: 7)))
        var relaxed = constraints()
        relaxed.enforceVariety = false
        #expect(AIOutputValidator.validate(week: WeekPlanDTO(prepSessions: [], days: days), constraints: relaxed).isValid)
    }

    @Test func draftMealsDecodeWithoutSteps() throws {
        let json = #"{"type":"lunch","name":"Poulet riz","ingredients":[],"prep_minutes":10,"cost_eur":2,"kcal":500,"#
            + #""protein_g":40,"carbs_g":50,"fat_g":15,"prep_session_ref":null,"time":"12:30"}"#
        let draft = try AIResponseDecoder.decoder.decode(MealDTO.self, from: Data(json.utf8))
        #expect(draft.steps.isEmpty)
        #expect(draft.needsRecipe)
    }

    @Test func weekSchemaUsesDraftMeals() throws {
        let defs = try #require(ResponseSchemas.schema(.week)["$defs"] as? [String: Any])
        let draft = try #require(defs["meal_draft"] as? [String: Any])
        #expect((draft["required"] as? [String])?.contains("steps") == false)
        let meal = try #require(defs["meal"] as? [String: Any])
        #expect((meal["required"] as? [String])?.contains("steps") == true)
        #expect(ResponseSchemas.schema(.recipe)["$defs"] == nil)
    }

    // MARK: Compléments

    @Test func dosesAreHostedAfterTraining() {
        let meals = [
            meal(.breakfast, time: "08:00"), meal(.lunch, time: "12:30"),
            meal(.snack, time: "18:45"), meal(.dinner, time: "20:30"),
        ]
        #expect(SupplementPlacement.hostIndex(in: meals, trainingTimeMinutes: 18 * 60) == 2)
        #expect(SupplementPlacement.hostIndex(in: meals, trainingTimeMinutes: nil) == 1)
        #expect(SupplementPlacement.hostIndex(in: meals, trainingTimeMinutes: 22 * 60) == 1)
        let creatine = OwnedSupplement(name: "Créatine", info: SupplementInfo(doseAmount: 5, doseUnit: .g, dosesPerDay: 1))
        #expect(SupplementPlacement.doses([creatine]) == ["Créatine : 5 g"])
    }
}

extension NutritionPipelineTests {
    @Test func missingFatIsToppedUpWithOil() {
        let lean = IngredientDTO(name: "Poulet, filet sans peau cru", quantity: 150, unit: "g", aisle: .viandePoisson, costEur: 1)
        let meals = [
            meal(.lunch, ingredients: [lean, rice(100)]), meal(.dinner, ingredients: [lean, rice(100)]),
        ].map { resolver.resolve($0).meal }
        let adjusted = PortionAdjuster.adjust(meals, to: referenceTargets, resolver: resolver)
        #expect(adjusted.allSatisfy { $0.ingredients.contains { $0.name == "Huile de colza" } })
        #expect(adjusted.allSatisfy { ($0.ingredients.first { $0.name == "Huile de colza" }?.quantity ?? 0) <= 20 })
        let without = PortionAdjuster.adjust(meals, to: referenceTargets, resolver: resolver, oil: nil)
        #expect(without.allSatisfy { !$0.ingredients.contains { $0.name == "Huile de colza" } })
    }
}

extension NutritionPipelineTests {
    @Test func renamedDishesAreStillRepeats() {
        let tuna = IngredientDTO(name: "Thon au naturel", quantity: 130, unit: "g", aisle: .epicerie, costEur: 1, foodCode: 26039)
        let pasta = IngredientDTO(name: "Pâtes", quantity: 100, unit: "g", aisle: .epicerie, costEur: 0.2, foodCode: 9810)
        let names = ["Pâtes au thon", "Thon à la tomate avec pâtes", "Pâtes tomate-thon express", "Thon et pâtes"]
        let days = names.enumerated().map { offset, name in
            DayPlanDTO(dayOffset: offset, meals: [meal(.dinner, name: name, ingredients: [tuna, pasta, oil()])])
        }
        #expect(VarietyCheck.signature(days[0].meals[0]) == ["pate", "thon"])
        #expect(Set(VarietyCheck.repeatedDays(days).keys) == [2, 3])
    }
}
