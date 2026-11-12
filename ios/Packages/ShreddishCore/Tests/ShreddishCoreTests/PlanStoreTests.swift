import Foundation
import SwiftData
import Testing
@testable import ShreddishCore

@MainActor
struct PlanStoreTests {
    static let start = LocalDay(year: 2026, month: 11, day: 11)

    // swiftlint:disable:next large_tuple
    static func setup() throws -> (ModelContainer, ModelContext, NutritionTargets) {
        let container = try ShreddishStore.makeContainer(inMemory: true)
        let targets = try NutritionCalculator.targets(for: NutritionCalculatorTests.man)
        return (container, container.mainContext, targets)
    }

    @Test func saveWeekCreatesSevenDaysFromGenerationDay() throws {
        let (container, context, targets) = try Self.setup()
        _ = container
        let plan = try PlanStore.saveWeek(try Fixture.week(), startDay: Self.start, targets: targets, createdAt: .now, in: context)
        #expect(plan.sortedDays.count == 7)
        #expect(plan.sortedDays.first?.day == Self.start)
        #expect(plan.sortedDays.last?.day == LocalDay(year: 2026, month: 11, day: 17))
        #expect(plan.sortedDays[0].sortedMeals.map(\.type) == [.breakfast, .lunch, .snack, .dinner])
        #expect(plan.targets?.targetKcal == 2207)
        #expect(PlanStore.currentPlan(in: context)?.id == plan.id)
    }

    @Test func newWeekKeepsPreviousInHistory() throws {
        let (container, context, targets) = try Self.setup()
        _ = container
        let first = try PlanStore.saveWeek(try Fixture.week(), startDay: Self.start, targets: targets, createdAt: .now, in: context)
        let second = try PlanStore.saveWeek(
            try Fixture.week(), startDay: Self.start.adding(days: 7), targets: targets, createdAt: .now.addingTimeInterval(60), in: context
        )
        #expect(!first.isCurrent)
        #expect(second.isCurrent)
        #expect(try context.fetchCount(FetchDescriptor<WeeklyPlan>()) == 2)
    }

    @Test func shoppingListKeepsCheckedItemsAfterReplacement() throws {
        let (container, context, targets) = try Self.setup()
        _ = container
        let plan = try PlanStore.saveWeek(try Fixture.week(), startDay: Self.start, targets: targets, createdAt: .now, in: context)
        let oats = try #require(plan.shoppingItems.first { $0.key.hasPrefix("flocon d'avoine") })
        #expect(oats.totalQuantity == 560)
        oats.isChecked = true

        let lunch = try #require(plan.sortedDays[2].sortedMeals.first { $0.type == .lunch })
        lunch.setStatus(.eaten, at: .now)
        let replacement = try PlanStore.replaceMeal(lunch, with: meal(.lunch, name: "Pâtes thon"), in: context)
        #expect(replacement?.status == .planned)
        #expect(replacement?.order == 1)
        #expect(plan.shoppingItems.first { $0.key.hasPrefix("flocon d'avoine") }?.isChecked == true)
        #expect(plan.sortedDays[2].meals.count == 4)
        #expect(plan.sortedDays[3].sortedMeals[1].name.hasPrefix("Poulet riz"))
    }

    @Test func actualTotalsUseStatusesAndExtras() throws {
        let (container, context, targets) = try Self.setup()
        _ = container
        let plan = try PlanStore.saveWeek(try Fixture.week(), startDay: Self.start, targets: targets, createdAt: .now, in: context)
        let day = plan.sortedDays[0]
        let meals = day.sortedMeals
        meals[1].setStatus(.eaten, at: .now)
        meals[3].setStatus(.skipped, at: .now)
        day.extras.append(ExtraEntry(name: "Carré de chocolat", quantityLabel: nil,
                                     macros: MacroTotals(kcal: 300, proteinG: 4, carbsG: 30, fatG: 18), loggedAt: .now))
        #expect(day.actualTotals.kcal == meals[1].kcal + 300)
    }
}
