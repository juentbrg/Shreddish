import Foundation

/// Réglages des rappels (spec 016), propres à l'appareil (UserDefaults, hors base).
public struct NotificationSettings: Codable, Equatable, Sendable {
    public static let leadOptions = [0, 10, 15, 30, 45, 60]

    public var mealsEnabled = true
    /// Avance sur l'heure du repas, en minutes.
    public var mealLeadMinutes = 0
    public var weighInEnabled = true
    /// Heures en minutes depuis minuit.
    public var weighInMinutes = 8 * 60
    public var planNextEnabled = true
    public var planNextMinutes = 18 * 60
    public var prepEnabled = true
    public var prepMinutes = 10 * 60
    public var shoppingEnabled = true
    public var shoppingMinutes = 10 * 60

    public init() {}

    public var anyEnabled: Bool { mealsEnabled || weighInEnabled || planNextEnabled || prepEnabled || shoppingEnabled }

    // Champs ajoutés plus tard : défaut si absents.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = NotificationSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        mealsEnabled = value(.mealsEnabled, defaults.mealsEnabled)
        mealLeadMinutes = value(.mealLeadMinutes, defaults.mealLeadMinutes)
        weighInEnabled = value(.weighInEnabled, defaults.weighInEnabled)
        weighInMinutes = value(.weighInMinutes, defaults.weighInMinutes)
        planNextEnabled = value(.planNextEnabled, defaults.planNextEnabled)
        planNextMinutes = value(.planNextMinutes, defaults.planNextMinutes)
        prepEnabled = value(.prepEnabled, defaults.prepEnabled)
        prepMinutes = value(.prepMinutes, defaults.prepMinutes)
        shoppingEnabled = value(.shoppingEnabled, defaults.shoppingEnabled)
        shoppingMinutes = value(.shoppingMinutes, defaults.shoppingMinutes)
    }
}

/// Nature d'un rappel : catégorie iOS et onglet ouvert au toucher.
public enum ReminderKind: String, Sendable, CaseIterable {
    case meal, weighIn, planNext, prep, shopping
}

/// Rappel à programmer.
public struct PlannedReminder: Equatable, Sendable {
    public var id: String
    public var kind: ReminderKind
    public var date: Date
    public var title: String
    public var body: String
    /// Cible du rappel : jour et rang du repas, ou début du planning (batch cooking).
    public var dayKey: Int?
    public var order: Int?
}

/// Données du planning utiles aux rappels, extraites de la base par l'app.
public struct ReminderInput: Sendable {
    public struct MealSlot: Sendable {
        public var day: LocalDay
        public var order: Int
        public var time: String?
        public var name: String
        public var typeLabel: String
        public var status: MealStatus

        public init(day: LocalDay, order: Int, time: String?, name: String, typeLabel: String, status: MealStatus) {
            self.day = day
            self.order = order
            self.time = time
            self.name = name
            self.typeLabel = typeLabel
            self.status = status
        }
    }

    public struct PlanSlot: Sendable {
        public var startDay: LocalDay
        public var endDay: LocalDay
        public var prepSessions: [PrepSessionDTO]
        public var uncheckedItems: Int

        public init(startDay: LocalDay, endDay: LocalDay, prepSessions: [PrepSessionDTO], uncheckedItems: Int) {
            self.startDay = startDay
            self.endDay = endDay
            self.prepSessions = prepSessions
            self.uncheckedItems = uncheckedItems
        }
    }

    public var meals: [MealSlot]
    public var plans: [PlanSlot]
    public var weighedDays: Set<LocalDay>

    public init(meals: [MealSlot], plans: [PlanSlot], weighedDays: Set<LocalDay>) {
        self.meals = meals
        self.plans = plans
        self.weighedDays = weighedDays
    }
}

/// Calcule les rappels des prochains jours (spec 016). iOS garde 64 rappels en attente au plus.
public enum NotificationPlanner {
    public static let horizonDays = 7
    public static let maxReminders = 60

    public static func reminders(
        settings: NotificationSettings, input: ReminderInput, now: Date, calendar: Calendar
    ) -> [PlannedReminder] {
        let window = Window(now: now, calendar: calendar)
        var reminders: [PlannedReminder] = []
        if settings.mealsEnabled { reminders += meals(input.meals, lead: settings.mealLeadMinutes, window: window) }
        if settings.weighInEnabled { reminders += weighIns(input.weighedDays, minutes: settings.weighInMinutes, window: window) }
        if settings.planNextEnabled, let reminder = planNext(input.plans, minutes: settings.planNextMinutes, window: window) {
            reminders.append(reminder)
        }
        if settings.prepEnabled { reminders += prepSessions(input.plans, minutes: settings.prepMinutes, window: window) }
        if settings.shoppingEnabled { reminders += shopping(input.plans, minutes: settings.shoppingMinutes, window: window) }
        return Array(reminders.sorted { $0.date < $1.date }.prefix(maxReminders))
    }

    /// Instant présent et horizon des rappels.
    struct Window {
        let now: Date
        let calendar: Calendar
        var today: LocalDay { LocalDay(date: now, calendar: calendar) }

        /// Date du rappel si elle est à venir et avant l'horizon.
        func upcoming(_ day: LocalDay, _ minutes: Int) -> Date? {
            let date = day.startDate(calendar: calendar).addingTimeInterval(TimeInterval(minutes * 60))
            return date > now && day < today.adding(days: horizonDays) ? date : nil
        }
    }

    static func meals(_ meals: [ReminderInput.MealSlot], lead: Int, window: Window) -> [PlannedReminder] {
        meals.compactMap { meal in
            guard meal.status == .planned, let minutes = SupplementPlacement.minutes(meal.time),
                  let date = window.upcoming(meal.day, minutes - lead) else { return nil }
            let leadText = lead > 0 ? " dans \(lead) min" : ""
            return PlannedReminder(
                id: "meal-\(meal.day.key)-\(meal.order)", kind: .meal, date: date,
                title: "\(meal.typeLabel)\(leadText) · \(meal.time ?? "")", body: meal.name,
                dayKey: meal.day.key, order: meal.order
            )
        }
    }

    static func weighIns(_ weighed: Set<LocalDay>, minutes: Int, window: Window) -> [PlannedReminder] {
        (0..<horizonDays).compactMap { offset in
            let day = window.today.adding(days: offset)
            guard !weighed.contains(day), let date = window.upcoming(day, minutes) else { return nil }
            return PlannedReminder(
                id: "weighin-\(day.key)", kind: .weighIn, date: date, title: "Pesée du matin",
                body: "Au réveil, à jeun, pour suivre ton rythme."
            )
        }
    }

    /// Veille du dernier jour planifié, ou ce jour-là si la veille est passée.
    static func planNext(_ plans: [ReminderInput.PlanSlot], minutes: Int, window: Window) -> PlannedReminder? {
        guard let end = plans.map(\.endDay).max() else { return nil }
        let id = "plannext-\(end.key)"
        if let date = window.upcoming(end.adding(days: -1), minutes) {
            return PlannedReminder(
                id: id, kind: .planNext, date: date, title: "Ton planning se termine demain",
                body: "Planifie la suite pour garder le rythme."
            )
        }
        guard let date = window.upcoming(end, minutes) else { return nil }
        return PlannedReminder(
            id: id, kind: .planNext, date: date, title: "Dernier jour de ton planning", body: "Planifie la suite pour demain."
        )
    }

    static func prepSessions(_ plans: [ReminderInput.PlanSlot], minutes: Int, window: Window) -> [PlannedReminder] {
        plans.flatMap { plan in
            plan.prepSessions.compactMap { session in
                let day = plan.startDay.adding(days: session.dayOffset)
                guard let date = window.upcoming(day, minutes) else { return nil }
                return PlannedReminder(
                    id: "prep-\(day.key)-\(session.index)", kind: .prep, date: date,
                    title: "Batch cooking aujourd'hui", body: "\(session.title) · \(session.durationMinutes) min",
                    dayKey: plan.startDay.key
                )
            }
        }
    }

    static func shopping(_ plans: [ReminderInput.PlanSlot], minutes: Int, window: Window) -> [PlannedReminder] {
        plans.compactMap { plan in
            let count = plan.uncheckedItems
            guard count > 0, let date = window.upcoming(plan.startDay, minutes) else { return nil }
            return PlannedReminder(
                id: "shopping-\(plan.startDay.key)", kind: .shopping, date: date, title: "Courses de la semaine",
                body: "\(count) article\(count > 1 ? "s" : "") à acheter sur ta liste."
            )
        }
    }
}
