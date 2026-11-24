import Foundation
import SwiftData
import Testing
@testable import ShreddishCore

/// Correctifs de la QA du 24/11/2026.
@MainActor
struct QAFixesTests {
    @Test func excludedFoodsMatchWholeWords() {
        let salad = MealDTO(
            type: .lunch, name: "Blanc de volaille et laitue", ingredients: [
                IngredientDTO(name: "Laitue", quantity: 50, unit: "g", aisle: .fruitsLegumes, costEur: 0),
                IngredientDTO(name: "Blanc de volaille", quantity: 120, unit: "g", aisle: .viandePoisson, costEur: 0),
            ], steps: [], prepMinutes: 5, costEur: 0, kcal: 200, proteinG: 30, carbsG: 2, fatG: 5, prepSessionRef: nil
        )
        #expect(AIOutputValidator.excludedFood(in: salad, excluded: ["lait", "ail"]) == nil)
        #expect(AIOutputValidator.excludedFood(in: salad, excluded: ["laitues"]) == "laitues")
        #expect(TextNormalizer.containsWords("Beurre d'arachides, crémeux", "arachide"))
        #expect(TextNormalizer.containsWords("Lait demi-écrémé", "lait"))
    }

    @Test func regeneratingADayKeepsLoggedMeals() throws {
        let (container, context, targets) = try PlanStoreTests.setup()
        _ = container
        let plan = try PlanStore.saveWeek(
            try Fixture.week(), startDay: PlanStoreTests.start, targets: targets, createdAt: .now, in: context
        )
        let day = try #require(plan.sortedDays.first)
        let eaten = try #require(day.sortedMeals.first)
        eaten.setStatus(.eaten, at: .now)
        eaten.eatenFraction = 0.5
        let eatenName = eaten.name
        let types = day.sortedMeals.map(\.type)
        let fresh = DayPlanDTO(dayOffset: 0, meals: try Fixture.week().days[1].meals)

        try PlanStore.replaceDay(day, with: fresh, in: context)

        #expect(day.sortedMeals.map(\.type) == types)
        #expect(day.sortedMeals.first?.name == eatenName)
        #expect(day.sortedMeals.first?.eatenFraction == 0.5)
        #expect(day.sortedMeals.dropFirst().allSatisfy { $0.status == .planned })
        #expect(day.sortedMeals.map(\.order) == Array(0..<types.count))
    }

    @Test func frozenFruitByThePieceIsBoughtFresh() {
        var banana = IngredientDTO(name: "Banane congelée", quantity: 2, unit: "piece", aisle: .surgeles, costEur: 0)
        banana.foodCode = 13005
        let line = ShoppingListBuilder.build(from: [banana]).first
        #expect(line?.totalQuantity == 2)
        #expect((line?.costEur ?? 99) < 2)
    }

    @Test func frozenVegetablesUseTheFrozenBagPrice() throws {
        var beans = IngredientDTO(name: "Haricots verts surgelés", quantity: 300, unit: "g", aisle: .surgeles, costEur: 0)
        beans.foodCode = 20061
        let line = try #require(ShoppingListBuilder.build(from: [beans]).first)
        let bag = try #require(PriceCatalog.shared.product(id: "legumes surgeles")?.price)
        #expect(line.costEur == BudgetMath.cents(bag * 0.75)) // sachet de 750 g
    }

    @Test func countedItemWithoutCodeIsNotTheWeighedProduct() {
        let onion = IngredientDTO(name: "Oignon", quantity: 1, unit: "piece", aisle: .fruitsLegumes, costEur: 0.4)
        let line = ShoppingListBuilder.build(from: [onion]).first
        #expect(ShoppingListBuilder.product(forKey: line?.key ?? "", prices: .shared) == nil)
        #expect(line?.costEur == 0.4)
    }

    @Test func plannedMealsAreRepricedFromTheTable() throws {
        let (container, context, targets) = try PlanStoreTests.setup()
        _ = container
        let plan = try PlanStore.saveWeek(
            try Fixture.week(), startDay: PlanStoreTests.start, targets: targets, createdAt: .now, in: context
        )
        let eaten = try #require(plan.sortedDays.first?.sortedMeals.first)
        eaten.setStatus(.eaten, at: .now)
        let planned = try #require(plan.sortedDays.first?.sortedMeals.last)
        var rice = IngredientDTO(name: "Riz basmati cru", quantity: 100, unit: "g", aisle: .epicerie, costEur: 9)
        rice.foodCode = 9100
        for meal in [eaten, planned] {
            meal.ingredientsData = try JSONEncoder().encode([rice])
            meal.costEUR = 9
        }
        PlanStore.repriceActivePlans(in: context)
        #expect(eaten.costEUR == 9)
        let price = try #require(PriceCatalog.shared.price(code: 9100))
        #expect(planned.costEUR == BudgetMath.cents(BudgetMath.cents(price.eurPerEdibleKg) / 10))
    }

    @Test func newWeekFromTodayKeepsTodaysLog() throws {
        let (container, context, targets) = try PlanStoreTests.setup()
        _ = container
        let today = PlanStoreTests.start.adding(days: 2)
        let old = try PlanStore.saveWeek(
            try Fixture.week(), startDay: PlanStoreTests.start, targets: targets, createdAt: .now, in: context
        )
        let oldToday = try #require(old.day(today))
        let breakfast = try #require(oldToday.sortedMeals.first)
        breakfast.setStatus(.eaten, at: .now)
        let eatenName = breakfast.name
        let mealCount = oldToday.meals.count
        let extra = ExtraEntry(
            name: "Carré de chocolat", quantityLabel: nil, macros: MacroTotals(kcal: 55, proteinG: 1, carbsG: 3, fatG: 4),
            loggedAt: .now
        )
        oldToday.extras.append(extra)

        let new = try PlanStore.saveWeek(
            try Fixture.week(), startDay: today, targets: targets, createdAt: .now, today: today, in: context
        )
        let newToday = try #require(new.day(today))
        #expect(newToday.sortedMeals.first?.name == eatenName)
        #expect(newToday.sortedMeals.first?.status == .eaten)
        #expect(newToday.meals.count == mealCount)
        #expect(newToday.extras.map(\.name) == ["Carré de chocolat"])
    }

    /// Spec 019 : liste sans les repas mangés tant que les courses ne sont pas validées, puis figée.
    @Test func shoppingFollowsEatenMealsUntilValidated() throws {
        let (container, context, targets) = try PlanStoreTests.setup()
        _ = container
        let plan = try PlanStore.saveWeek(
            try Fixture.week(), startDay: PlanStoreTests.start, targets: targets, createdAt: .now, in: context
        )
        func total() -> Double { plan.shoppingItems.reduce(0) { $0 + $1.totalQuantity } }
        let full = total()
        let fullCost = PlanStore.fullShoppingSummary(for: plan, in: context).checkoutEur
        for meal in plan.sortedDays.prefix(2).flatMap(\.meals) { meal.setStatus(.eaten, at: .now) }
        PlanStore.rebuildStaleShoppingList(for: plan, in: context)
        let remaining = total()
        #expect(remaining < full)
        #expect(PlanStore.fullShoppingSummary(for: plan, in: context).checkoutEur == fullCost)

        for item in plan.shoppingItems { item.isChecked = true }
        ShoppingValidation.validate(plan, at: .now, in: context)
        for meal in plan.sortedDays[2].meals { meal.setStatus(.eaten, at: .now) }
        PlanStore.rebuildStaleShoppingList(for: plan, in: context)
        #expect(total() == remaining)
        #expect(plan.shoppingItems.allSatisfy { $0.isChecked })

        ShoppingValidation.reopen(plan, in: context)
        #expect(total() < remaining)
        #expect(!PlanStore.isShoppingValidated(plan, in: context))
    }

    @Test func endedPlansShoppingIsFrozenAtLaunch() throws {
        let (container, context, targets) = try PlanStoreTests.setup()
        _ = container
        let plan = try PlanStore.saveWeek(
            try Fixture.week(), startDay: PlanStoreTests.start, targets: targets, createdAt: .now, in: context
        )
        let count = plan.shoppingItems.count
        #expect(PlanStore.validatePastShopping(today: PlanStoreTests.start.adding(days: 3), in: context) == 0)
        #expect(PlanStore.validatePastShopping(today: PlanStoreTests.start.adding(days: 7), in: context) == 1)
        for meal in plan.days.flatMap(\.meals) { meal.setStatus(.eaten, at: .now) }
        PlanStore.rebuildStaleShoppingList(for: plan, in: context)
        #expect(plan.shoppingItems.count == count)
    }
}
