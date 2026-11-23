import Foundation
import SwiftData
import Testing
@testable import ShreddishCore

/// Période choisie (premier et dernier jour) : seuls ses jours sont remplacés dans les plannings actifs.
@MainActor
struct PlanRangeTests {
    static let sunday = LocalDay(year: 2026, month: 11, day: 22)

    static func days(_ count: Int) throws -> WeekPlanDTO {
        WeekPlanDTO(prepSessions: [], days: Array(try Fixture.week().days.prefix(count)))
    }

    @Test func mondayToSundayKeepsYesterdayAndFollowingWeek() throws {
        let container = try ShreddishStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let targets = try NutritionCalculator.targets(for: NutritionCalculatorTests.man)
        let monday = Self.sunday.adding(days: 1)
        let current = try PlanStore.saveWeek(
            try Fixture.week(), startDay: Self.sunday, targets: targets, createdAt: .now, in: context
        )
        let following = try PlanStore.saveWeek(
            try Fixture.week(), startDay: Self.sunday.adding(days: 7), targets: targets, createdAt: .now.addingTimeInterval(1),
            today: Self.sunday, in: context
        )
        current.sortedDays[1].sortedMeals[0].setStatus(.eaten, at: .now)

        let plan = try PlanStore.saveWeek(
            try Fixture.week(), startDay: monday, targets: targets, createdAt: .now.addingTimeInterval(2), today: monday, in: context
        )

        #expect(plan.sortedDays.map(\.day) == (0...6).map { monday.adding(days: $0) })
        // Hier reste dans son planning, terminé donc en historique.
        #expect(current.sortedDays.map(\.day) == [Self.sunday])
        #expect(!current.isCurrent)
        // Semaine suivante : dimanche repris, le reste intact et recalé.
        #expect(following.isCurrent)
        #expect(following.startDay == Self.sunday.adding(days: 8))
        #expect(following.sortedDays.map(\.offset) == Array(0...5))
        // Aujourd'hui, déjà journalisé : archivé, journal conservé.
        let archived = try context.fetch(FetchDescriptor<WeeklyPlan>()).filter { !$0.isCurrent && $0.id != current.id }
        #expect(archived.count == 1)
        #expect(archived.first?.sortedDays.map(\.day) == [monday])
        #expect(archived.first?.sortedDays.first?.meals.contains { $0.status == .eaten } == true)
        #expect(PlanStore.activePlans(in: context).map(\.id) == [plan.id, following.id])
    }

    @Test func shortRangeInsideWeekSplitsTheRest() throws {
        let container = try ShreddishStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let targets = try NutritionCalculator.targets(for: NutritionCalculatorTests.man)
        let week = try PlanStore.saveWeek(try Fixture.week(), startDay: Self.sunday, targets: targets, createdAt: .now, in: context)

        let plan = try PlanStore.saveWeek(
            try Self.days(2), startDay: Self.sunday.adding(days: 2), targets: targets, createdAt: .now.addingTimeInterval(1),
            today: Self.sunday, in: context
        )

        #expect(plan.sortedDays.count == 2)
        #expect(week.sortedDays.map(\.day) == [Self.sunday, Self.sunday.adding(days: 1)])
        let active = PlanStore.activePlans(in: context)
        #expect(active.count == 3)
        let tail = try #require(active.last)
        #expect(tail.startDay == Self.sunday.adding(days: 4))
        #expect(tail.sortedDays.map(\.offset) == [0, 1, 2])
        #expect(!tail.shoppingItems.isEmpty)
        // Aucun jour supprimé hors de la période.
        #expect(try context.fetchCount(FetchDescriptor<DayPlan>()) == 7)
    }
}
