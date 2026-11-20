import Foundation
import Testing
@testable import ShreddishCore

/// Rappels (spec 016).
struct NotificationPlannerTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()
    let today = LocalDay(year: 2026, month: 11, day: 19)

    func at(_ day: LocalDay, _ hour: Int, _ minute: Int = 0) -> Date {
        day.startDate(calendar: calendar).addingTimeInterval(TimeInterval((hour * 60 + minute) * 60))
    }

    func slot(_ day: LocalDay, _ order: Int, _ time: String?, status: MealStatus = .planned) -> ReminderInput.MealSlot {
        .init(day: day, order: order, time: time, name: "Poulet riz", typeLabel: "Déjeuner", status: status)
    }

    func plan(start: LocalDay, sessions: [PrepSessionDTO] = [], unchecked: Int = 0) -> ReminderInput.PlanSlot {
        .init(startDay: start, endDay: start.adding(days: 6), prepSessions: sessions, uncheckedItems: unchecked)
    }

    func reminders(
        _ settings: NotificationSettings = NotificationSettings(), meals: [ReminderInput.MealSlot] = [],
        plans: [ReminderInput.PlanSlot] = [], weighed: Set<LocalDay> = [], now: Date
    ) -> [PlannedReminder] {
        NotificationPlanner.reminders(
            settings: settings, input: ReminderInput(meals: meals, plans: plans, weighedDays: weighed),
            now: now, calendar: calendar
        )
    }

    @Test func plannedFutureMealsOnly() {
        var settings = NotificationSettings()
        settings.weighInEnabled = false
        settings.planNextEnabled = false
        let meals = [
            slot(today, 0, "08:00"), slot(today, 1, "12:30"), slot(today, 2, "19:00", status: .eaten),
            slot(today, 3, nil), slot(today.adding(days: 8), 0, "12:30"),
        ]
        let result = reminders(settings, meals: meals, now: at(today, 10))
        #expect(result.map(\.id) == ["meal-20261119-1"])
        #expect(result.first?.date == at(today, 12, 30))
        #expect(result.first?.title == "Déjeuner · 12:30")
        #expect(result.first?.order == 1)
    }

    @Test func mealLeadTimeIsApplied() {
        var settings = NotificationSettings()
        settings.mealLeadMinutes = 15
        settings.weighInEnabled = false
        settings.planNextEnabled = false
        let result = reminders(settings, meals: [slot(today, 1, "12:30")], now: at(today, 10))
        #expect(result.first?.date == at(today, 12, 15))
        #expect(result.first?.title == "Déjeuner" + String(localized: " dans \(15) min", bundle: CoreResources.bundle) + " · 12:30")
    }

    @Test func weighInSkipsWeighedDaysAndPastTimes() {
        var settings = NotificationSettings()
        settings.mealsEnabled = false
        let result = reminders(settings, weighed: [today.adding(days: 1)], now: at(today, 9))
        let days = result.filter { $0.kind == .weighIn }.map(\.id)
        #expect(days.count == 5)
        #expect(!days.contains("weighin-20261119"))
        #expect(!days.contains("weighin-20261120"))
    }

    @Test func planNextTheDayBeforeTheLastPlanEnds() {
        var settings = NotificationSettings()
        settings.weighInEnabled = false
        let plans = [plan(start: today.adding(days: -4)), plan(start: today.adding(days: -10))]
        let result = reminders(settings, plans: plans, now: at(today, 9))
        let reminder = result.first { $0.kind == .planNext }
        #expect(reminder?.date == at(today.adding(days: 1), 18))
        #expect(reminder?.title == String(localized: "Ton planning se termine demain", bundle: CoreResources.bundle))
    }

    @Test func planNextOnLastDayWhenTheDayBeforeIsPast() {
        var settings = NotificationSettings()
        settings.weighInEnabled = false
        let result = reminders(settings, plans: [plan(start: today.adding(days: -6))], now: at(today, 9))
        #expect(result.first { $0.kind == .planNext }?.date == at(today, 18))
    }

    @Test func prepAndShoppingOnTheirDays() {
        var settings = NotificationSettings()
        settings.weighInEnabled = false
        settings.planNextEnabled = false
        let start = today.adding(days: 2)
        let session = PrepSessionDTO(index: 0, dayOffset: 0, title: "Poulet et riz", durationMinutes: 60, steps: [])
        let result = reminders(settings, plans: [plan(start: start, sessions: [session], unchecked: 3)], now: at(today, 9))
        #expect(result.map(\.kind) == [.prep, .shopping])
        #expect(result.allSatisfy { $0.date == at(start, 10) })
        #expect(result.last?.body == String(localized: "\(3) articles à acheter sur ta liste.", bundle: CoreResources.bundle))
        #expect(result.first?.dayKey == start.key)
    }

    @Test func everythingOffMeansNoReminder() {
        var settings = NotificationSettings()
        settings.mealsEnabled = false
        settings.weighInEnabled = false
        settings.planNextEnabled = false
        settings.prepEnabled = false
        settings.shoppingEnabled = false
        #expect(!settings.anyEnabled)
        #expect(reminders(settings, meals: [slot(today, 1, "12:30")], plans: [plan(start: today, unchecked: 2)], now: at(today, 6))
            .isEmpty)
    }

    @Test func settingsDecodeWithMissingFields() throws {
        let decoded = try JSONDecoder().decode(NotificationSettings.self, from: Data(#"{"mealsEnabled":false}"#.utf8))
        #expect(!decoded.mealsEnabled)
        #expect(decoded.weighInMinutes == 8 * 60)
    }
}
