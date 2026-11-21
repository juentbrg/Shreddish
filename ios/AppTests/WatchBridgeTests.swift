import Foundation
import ShreddishCore
import SwiftData
import Testing
@testable import Shreddish

/// Apple Watch (spec 017, FR-1711) : journée envoyée et actions de la montre appliquées.
@MainActor
struct WatchBridgeTests {
    let model = AppModel(clock: SystemClock(), keyStore: InMemoryKeyStore(key: nil), transport: UITestAITransport(), isUITest: true)
    let container: ModelContainer

    init() throws {
        container = try ShreddishStore.makeContainer(inMemory: true)
        model.watch.attach(model: model, container: container)
        let birth = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
        let profile = Profile(sex: .male, birthDate: birth, heightCm: 180, weightKg: 80, activity: .moderate, goal: .cut)
        let targets = try #require(profile.targets(clock: SystemClock()))
        let meal = MealDTO(
            type: .lunch, name: "Poulet riz", ingredients: [], steps: ["Cuire."], prepMinutes: 15, costEur: 2,
            kcal: 600, proteinG: 45, carbsG: 60, fatG: 15, prepSessionRef: nil, time: "12:30"
        )
        try PlanStore.saveWeek(
            WeekPlanDTO(prepSessions: [], days: [DayPlanDTO(dayOffset: 0, meals: [meal])]),
            startDay: model.clock.today, targets: targets, createdAt: .now, in: container.mainContext
        )
    }

    @Test func todayIsSentWithTargetsAndMeals() {
        let day = WatchBridge.today(in: container.mainContext, clock: model.clock)
        #expect(day.meals.map(\.name) == ["Poulet riz"])
        #expect(day.meals.first?.time == "12:30")
        #expect(day.targetKcal > 0)
        #expect(day.eatenKcal == 0)
        #expect(WatchDay.decode(day.encoded()) == day)
    }

    @Test func watchActionsAreApplied() throws {
        model.watch.apply(.mealStatus(dayKey: model.clock.today.key, order: 0, status: "eaten"))
        let meal = try #require(PlanStore.currentPlan(in: container.mainContext)?.days.first?.meals.first)
        #expect(meal.status == .eaten)
        model.watch.apply(.weight(kg: 79.4))
        let weights = try container.mainContext.fetch(FetchDescriptor<WeightEntry>())
        #expect(weights.first?.weightKg == 79.4)
        let day = WatchBridge.today(in: container.mainContext, clock: model.clock)
        #expect(day.eatenKcal == 600)
        #expect(day.weighedToday)
    }
}
