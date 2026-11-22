import Foundation
import SwiftData
import Testing
@testable import ShreddishCore

/// Restes déjà achetés reportés sur les courses de la semaine suivante (spec 017, FR-1706).
@MainActor
struct ShoppingCarryOverTests {
    @Test func checkedLeftoversAreDeductedFromNextWeek() throws {
        let (container, context, targets) = try PlanStoreTests.setup()
        _ = container
        let first = try PlanStore.saveWeek(
            try Fixture.week(), startDay: PlanStoreTests.start, targets: targets, createdAt: .now, in: context
        )
        let second = try PlanStore.saveWeek(
            try Fixture.week(), startDay: PlanStoreTests.start.adding(days: 7), targets: targets, createdAt: .now, in: context
        )
        #expect(PlanStore.previousPlan(before: second, in: context)?.id == first.id)
        // Rien de coché : rien de reporté.
        #expect(PlanStore.carriedStock(for: second, in: context).isEmpty)
        let before = Dictionary(uniqueKeysWithValues: second.shoppingItems.map { ($0.key, $0.totalQuantity) })

        for item in first.shoppingItems { item.isChecked = true }
        let carried = PlanStore.carriedStock(for: second, in: context)
        try #require(!carried.isEmpty, "la semaine type doit laisser des paquets entamés non périssables")
        PlanStore.rebuildFollowingShoppingList(after: first, in: context)
        let after = Dictionary(uniqueKeysWithValues: second.shoppingItems.map { ($0.key, $0.totalQuantity) })
        #expect(after.contains { key, quantity in quantity < (before[key] ?? 0) })
        #expect(after.allSatisfy { key, quantity in quantity <= (before[key] ?? .infinity) })
    }

    @Test func perishableLeftoversAreNotCarried() throws {
        let (container, context, targets) = try PlanStoreTests.setup()
        _ = container
        let first = try PlanStore.saveWeek(
            try Fixture.week(), startDay: PlanStoreTests.start, targets: targets, createdAt: .now, in: context
        )
        let second = try PlanStore.saveWeek(
            try Fixture.week(), startDay: PlanStoreTests.start.adding(days: 7), targets: targets, createdAt: .now, in: context
        )
        for item in first.shoppingItems { item.isChecked = true }
        let perishable = Set(first.shoppingItems.filter(\.packing.perishable).map { TextNormalizer.singular($0.name) })
        let carried = Set(PlanStore.carriedStock(for: second, in: context).map { TextNormalizer.singular($0.name) })
        #expect(carried.isDisjoint(with: perishable))
    }
}

/// Ingrédients des repas non mangés des jours passés, proposés à l'écoulement.
@MainActor
struct UneatenIngredientsTests {
    @Test func onlyPastUneatenMealsAreSuggested() throws {
        let (container, context, targets) = try PlanStoreTests.setup()
        _ = container
        let plan = try PlanStore.saveWeek(
            try Fixture.week(), startDay: PlanStoreTests.start, targets: targets, createdAt: .now, in: context
        )
        let today = PlanStoreTests.start.adding(days: 1)
        let day0 = try #require(plan.sortedDays.first)
        for meal in day0.sortedMeals { meal.status = .eaten }
        #expect(PlanStore.uneatenIngredients(in: [plan], before: today).isEmpty)
        let skipped = try #require(day0.sortedMeals.first)
        skipped.status = .skipped
        let names = Set(PlanStore.uneatenIngredients(in: [plan], before: today).map(\.name))
        #expect(names == Set(skipped.ingredients.map(\.name)))
    }
}
