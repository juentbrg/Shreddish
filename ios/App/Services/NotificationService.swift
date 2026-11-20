import Foundation
import Observation
import ShreddishCore
import SwiftData
import UserNotifications

/// Rappels locaux (spec 016) : repas, pesée, suite du planning, batch cooking, courses.
/// Tout est recalculé à chaque passage au premier plan ou en arrière-plan : aucun rappel périmé.
@MainActor
@Observable
final class NotificationService: NSObject {
    static let settingsKey = "notificationSettings"
    static let mealCategory = "MEAL"
    static let eatenAction = "MEAL_EATEN"
    static let skippedAction = "MEAL_SKIPPED"

    private let center: UNUserNotificationCenter?
    private let defaults: UserDefaults
    private weak var model: AppModel?
    private var container: ModelContainer?

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    var settings: NotificationSettings {
        didSet {
            guard settings != oldValue else { return }
            if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.settingsKey) }
            Task { await reschedule() }
        }
    }

    /// `enabled` faux (tests d'interface) : aucune demande d'autorisation ni rappel.
    init(enabled: Bool, defaults: UserDefaults = .standard) {
        center = enabled ? UNUserNotificationCenter.current() : nil
        self.defaults = defaults
        settings = defaults.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(NotificationSettings.self, from: $0) } ?? NotificationSettings()
        super.init()
        guard let center else { return }
        center.delegate = self
        let eaten = UNNotificationAction(identifier: Self.eatenAction, title: String(localized: "Mangé"))
        let skipped = UNNotificationAction(identifier: Self.skippedAction, title: String(localized: "Sauté"))
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.mealCategory, actions: [eaten, skipped], intentIdentifiers: []),
        ])
    }

    func attach(model: AppModel, container: ModelContainer) {
        self.model = model
        self.container = container
    }

    /// Autorisation demandée une fois, quand un profil existe (après l'accueil).
    func requestAuthorizationIfNeeded() async {
        guard let center else { return }
        authorization = await center.notificationSettings().authorizationStatus
        guard authorization == .notDetermined, settings.anyEnabled, hasProfile else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Remplace tous les rappels en attente par ceux calculés depuis la base.
    func reschedule() async {
        guard let center, let container, let model else { return }
        authorization = await center.notificationSettings().authorizationStatus
        center.removeAllPendingNotificationRequests()
        guard [.authorized, .provisional, .ephemeral].contains(authorization) else { return }
        let input = Self.input(in: container.mainContext)
        let reminders = NotificationPlanner.reminders(
            settings: settings, input: input, now: model.clock.now, calendar: model.clock.calendar
        )
        for reminder in reminders {
            try? await center.add(Self.request(reminder, calendar: model.clock.calendar))
        }
    }

    private var hasProfile: Bool {
        guard let context = container?.mainContext else { return false }
        return ((try? context.fetchCount(FetchDescriptor<Profile>())) ?? 0) > 0
    }

    static func input(in context: ModelContext) -> ReminderInput {
        let plans = PlanStore.activePlans(in: context)
        let meals = plans.flatMap(\.days).flatMap { day in
            day.sortedMeals.map { meal in
                ReminderInput.MealSlot(
                    day: day.day, order: meal.order, time: meal.time, name: meal.name, typeLabel: meal.type.label,
                    status: meal.status
                )
            }
        }
        let slots = plans.map { plan in
            ReminderInput.PlanSlot(
                startDay: plan.startDay, endDay: plan.endDay, prepSessions: plan.prepSessions,
                uncheckedItems: plan.shoppingItems.filter { !$0.isChecked }.count
            )
        }
        let weighed = Set(((try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []).map(\.day))
        return ReminderInput(meals: meals, plans: slots, weighedDays: weighed)
    }

    static func request(_ reminder: PlannedReminder, calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.threadIdentifier = reminder.kind.rawValue
        var info: [String: Any] = ["kind": reminder.kind.rawValue]
        if let day = reminder.dayKey { info["dayKey"] = day }
        if let order = reminder.order { info["order"] = order }
        if reminder.kind == .meal { content.categoryIdentifier = mealCategory }
        content.userInfo = info
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
    }

    /// Action d'un rappel : statut du repas, ou onglet ouvert au toucher.
    func handle(action: String, kind: String?, dayKey: Int?, order: Int?) async {
        guard let container, let model else { return }
        if [Self.eatenAction, Self.skippedAction].contains(action), let dayKey, let order {
            let context = container.mainContext
            let meal = PlanStore.activePlans(in: context).flatMap(\.days).first { $0.dayKey == dayKey }?
                .meals.first { $0.order == order }
            meal?.setStatus(action == Self.eatenAction ? .eaten : .skipped, at: model.clock.now)
            try? context.save()
            await reschedule()
            return
        }
        switch kind.flatMap(ReminderKind.init(rawValue:)) {
        case .meal:
            model.selectedTab = .week
            if let dayKey, let order { model.deepLink = .meal(MealRef(dayKey: dayKey, order: order)) }
        case .planNext:
            model.selectedTab = .week
            model.deepLink = .planNext
        case .prep:
            model.selectedTab = .week
            if let dayKey { model.deepLink = .prep(planStartKey: dayKey) }
        case .weighIn:
            model.selectedTab = .targets
            model.deepLink = .weighIn
        case .shopping:
            model.selectedTab = .shopping
        case nil: break
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Version à completion : UIKit exige l'appel sur le fil principal (la version async le fait hors du fil
    /// principal et l'app plantait au toucher d'une notification).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let kind = info["kind"] as? String
        let dayKey = info["dayKey"] as? Int
        let order = info["order"] as? Int
        Task { @MainActor in
            await self.handle(action: action, kind: kind, dayKey: dayKey, order: order)
            completionHandler()
        }
    }
}
