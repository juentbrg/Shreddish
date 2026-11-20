import Foundation
import ShreddishCore
import SwiftData
import Testing
@testable import Shreddish

/// Toucher d'un rappel (spec 016).
@MainActor
struct NotificationServiceTests {
    let model = AppModel(clock: SystemClock(), keyStore: InMemoryKeyStore(key: nil), transport: UITestAITransport(), isUITest: true)
    let container: ModelContainer

    init() throws {
        container = try ShreddishStore.makeContainer(inMemory: true)
        model.notifications.attach(model: model, container: container)
        let meal = MealDTO(
            type: .lunch, name: "Poulet riz",
            ingredients: [IngredientDTO(name: "Riz", quantity: 80, unit: "g", aisle: .epicerie, costEur: 0.2)],
            steps: ["Cuire."], prepMinutes: 15, costEur: 2, kcal: 500, proteinG: 40, carbsG: 50, fatG: 15,
            prepSessionRef: nil, time: "12:30"
        )
        let birth = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
        let profile = Profile(sex: .male, birthDate: birth, heightCm: 180, weightKg: 80, activity: .moderate, goal: .cut)
        let targets = try #require(profile.targets(clock: SystemClock()))
        try PlanStore.saveWeek(
            WeekPlanDTO(prepSessions: [], days: [DayPlanDTO(dayOffset: 0, meals: [meal])]),
            startDay: model.clock.today, targets: targets, createdAt: .now, in: container.mainContext
        )
    }

    private var meal: Meal? {
        PlanStore.activePlans(in: container.mainContext).first?.days.first?.meals.first
    }

    @Test func tappingAMealReminderOpensItsRecipe() async throws {
        model.selectedTab = .journal
        let meal = try #require(meal)
        await model.notifications.handle(
            action: "com.apple.UNNotificationDefaultActionIdentifier", kind: "meal",
            dayKey: model.clock.today.key, order: meal.order
        )
        #expect(model.selectedTab == .week)
        #expect(model.deepLink == .meal(MealRef(dayKey: model.clock.today.key, order: meal.order)))
    }

    @Test func eatenActionLogsTheMeal() async throws {
        let meal = try #require(meal)
        await model.notifications.handle(
            action: NotificationService.eatenAction, kind: "meal", dayKey: model.clock.today.key, order: meal.order
        )
        #expect(meal.status == .eaten)
        #expect(model.deepLink == nil)
    }

    @Test func eachReminderOpensItsFeature() async {
        struct Case {
            let kind: String
            let tab: AppModel.Tab
            let link: DeepLink?
        }
        let cases = [
            Case(kind: "planNext", tab: .week, link: .planNext),
            Case(kind: "prep", tab: .week, link: .prep(planStartKey: 20_261_122)),
            Case(kind: "weighIn", tab: .targets, link: .weighIn), Case(kind: "shopping", tab: .shopping, link: nil),
        ]
        for item in cases {
            let (kind, tab, link) = (item.kind, item.tab, item.link)
            model.deepLink = nil
            await model.notifications.handle(
                action: "com.apple.UNNotificationDefaultActionIdentifier", kind: kind, dayKey: 20_261_122, order: nil
            )
            #expect(model.selectedTab == tab)
            #expect(model.deepLink == link)
        }
    }
}
