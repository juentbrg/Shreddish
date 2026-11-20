import Foundation
import SwiftData
import Testing
@testable import ShreddishCore

/// Foyer (spec 017, FR-1704).
@MainActor
struct HouseholdTests {
    struct FixedClock: AppClock {
        var now = Date(timeIntervalSince1970: 1_795_000_000)
        var calendar = Calendar(identifier: .gregorian)
    }

    @Test func portionsAddUp() {
        let members = [HouseholdMember(name: "Léa", portion: 0.75), HouseholdMember(name: "Tom", portion: 0.5)]
        #expect(Household.portions(members) == 2.25)
        #expect(Household.portions([]) == 1)
    }

    @Test func portionIsClamped() {
        #expect(HouseholdMember(name: "A", portion: 5).portion == HouseholdMember.portionRange.upperBound)
    }

    @Test func profilePortionFollowsKcal() throws {
        let member = HouseholdMember(name: "Léa")
        member.sexRaw = Sex.female.rawValue
        member.birthDate = Calendar(identifier: .gregorian).date(byAdding: .year, value: -30, to: FixedClock().now)
        member.heightCm = 165
        member.weightKg = 60
        member.activityRaw = ActivityLevel.moderate.rawValue
        member.goalRaw = Goal.recomp.rawValue
        let kcal = try #require(member.targets(clock: FixedClock())?.targetKcal)
        member.refreshPortion(mainKcal: kcal * 2, clock: FixedClock())
        #expect(abs(member.portion - 0.5) < 0.01)
    }

    @Test func scaledIngredientsMultiplyQuantityAndCost() {
        let scaled = Household.scaled([ingredient("Riz", 80, cost: 0.2)], portions: 2.5)
        #expect(scaled.first?.quantity == 200)
        #expect(scaled.first?.costEur == 0.5)
    }

    @Test func shoppingListCoversTheHousehold() throws {
        let container = try ShreddishStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let targets = try NutritionCalculator.targets(for: NutritionCalculatorTests.man)
        let riz = ingredient("Riz basmati cru", 100, cost: 0.3)
        let plan = try PlanStore.saveWeek(
            WeekPlanDTO(prepSessions: [], days: [DayPlanDTO(dayOffset: 0, meals: [meal(ingredients: [riz])])]),
            startDay: LocalDay(year: 2026, month: 11, day: 20), targets: targets, createdAt: .now, in: context
        )
        let alone = try #require(plan.shoppingItems.first).totalQuantity
        plan.shoppingItems.first?.isChecked = true
        context.insert(HouseholdMember(name: "Léa", portion: 1))
        PlanStore.rebuildActiveShoppingLists(in: context)
        let item = try #require(plan.shoppingItems.first)
        #expect(abs(item.totalQuantity - alone * 2) < 0.01)
        #expect(item.isChecked)
    }
}
