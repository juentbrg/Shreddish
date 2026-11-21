import Foundation
import ShreddishCore
import SwiftData
import WatchConnectivity

/// Pont avec l'Apple Watch (spec 017, FR-1711) : la journée en cours part vers la montre, les repas cochés
/// et les pesées faites sur la montre reviennent ici. Rien ne passe par internet.
@MainActor
final class WatchBridge: NSObject {
    private let session: WCSession?
    private weak var model: AppModel?
    private var container: ModelContainer?

    init(enabled: Bool) {
        session = enabled && WCSession.isSupported() ? WCSession.default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func attach(model: AppModel, container: ModelContainer) {
        self.model = model
        self.container = container
    }

    /// Journée du jour envoyée à la montre (dernier état seulement : applicationContext).
    func push() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let container, let model else { return }
        let day = Self.today(in: container.mainContext, clock: model.clock)
        try? session.updateApplicationContext(day.encoded())
    }

    static func today(in context: ModelContext, clock: any AppClock) -> WatchDay {
        let today = clock.today
        let plans = PlanStore.activePlans(in: context)
        let day = plans.flatMap(\.days).first { $0.day == today }
        let targets = day?.plan?.targets ?? plans.last?.targets
        let actual = day?.actualTotals ?? .zero
        let weights = ((try? context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.dayKey)]))) ?? [])
        return WatchDay(
            dayKey: today.key,
            meals: (day?.sortedMeals ?? []).map { meal in
                WatchDay.Meal(
                    dayKey: today.key, order: meal.order, time: meal.time, typeLabel: meal.type.label, name: meal.name,
                    kcal: Int(meal.kcal.rounded()), proteinG: Int(meal.proteinG.rounded()), status: meal.statusRaw
                )
            },
            targetKcal: targets?.targetKcal ?? 0, targetProteinG: targets?.proteinG ?? 0,
            eatenKcal: Int(actual.kcal.rounded()), eatenProteinG: Int(actual.proteinG.rounded()),
            lastWeightKg: weights.last?.weightKg, weighedToday: weights.last?.dayKey == today.key, updatedAt: clock.now
        )
    }

    /// Action de la montre : statut d'un repas ou pesée du jour.
    func apply(_ action: WatchAction) {
        guard let container, let model else { return }
        let context = container.mainContext
        switch action {
        case let .mealStatus(dayKey, order, status):
            let meal = PlanStore.activePlans(in: context).flatMap(\.days).first { $0.dayKey == dayKey }?
                .meals.first { $0.order == order }
            meal?.setStatus(MealStatus(rawValue: status) ?? .planned, at: model.clock.now)
            meal?.eatenFraction = nil
        case let .weight(kg):
            guard NutritionCalculator.weightRange.contains(kg) else { return }
            let today = model.clock.today
            let entries = (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []
            if let existing = entries.first(where: { $0.dayKey == today.key }) {
                existing.weightKg = kg
                existing.recordedAt = model.clock.now
            } else {
                context.insert(WeightEntry(day: today, weightKg: kg, recordedAt: model.clock.now))
            }
        }
        try? context.save()
        push()
        Task { await model.notifications.reschedule() }
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in self.push() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.push() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let action = WatchAction.decode(message) else { return }
        Task { @MainActor in self.apply(action) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let action = WatchAction.decode(userInfo) else { return }
        Task { @MainActor in self.apply(action) }
    }
}
