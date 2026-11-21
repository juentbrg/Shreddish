import Foundation
import Observation
import WatchConnectivity

/// Journée reçue de l'iPhone (gardée hors ligne) et actions renvoyées.
@MainActor
@Observable
final class WatchStore: NSObject {
    private(set) var day: WatchDay?
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private static let cacheKey = "watchDayCache"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey) {
            day = try? JSONDecoder().decode(WatchDay.self, from: data)
        }
        // Journée de démonstration (captures, simulateur sans iPhone).
        if ProcessInfo.processInfo.arguments.contains("-demo") { day = Self.demo }
        session?.delegate = self
        session?.activate()
    }

    /// Repas du jour seulement si la journée reçue est bien aujourd'hui.
    var isToday: Bool {
        guard let day else { return false }
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return day.dayKey == (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    static var demo: WatchDay {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        let key = (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
        return WatchDay(
            dayKey: key,
            meals: [
                .init(dayKey: key, order: 0, time: "12:30", typeLabel: "Déjeuner", name: "Poulet, riz et brocolis", kcal: 640,
                      proteinG: 48, status: "eaten"),
                .init(dayKey: key, order: 1, time: "16:30", typeLabel: "Collation", name: "Skyr, banane", kcal: 280,
                      proteinG: 25, status: "planned"),
                .init(dayKey: key, order: 2, time: "19:00", typeLabel: "Dîner", name: "Omelette, patate douce", kcal: 610,
                      proteinG: 42, status: "planned"),
            ],
            targetKcal: 1834, targetProteinG: 160, eatenKcal: 640, eatenProteinG: 48, lastWeightKg: 80.4,
            weighedToday: false, updatedAt: .now
        )
    }

    func setStatus(_ meal: WatchDay.Meal, _ status: String) {
        let newStatus = meal.status == status ? "planned" : status
        update { day in
            guard let index = day.meals.firstIndex(where: { $0.id == meal.id }) else { return }
            let sign = newStatus == "eaten" ? 1 : (meal.status == "eaten" ? -1 : 0)
            day.eatenKcal += sign * meal.kcal
            day.eatenProteinG += sign * meal.proteinG
            day.meals[index].status = newStatus
        }
        send(.mealStatus(dayKey: meal.dayKey, order: meal.order, status: newStatus))
    }

    func logWeight(_ kg: Double) {
        update { day in
            day.lastWeightKg = kg
            day.weighedToday = true
        }
        send(.weight(kg: kg))
    }

    private func update(_ change: (inout WatchDay) -> Void) {
        guard var current = day else { return }
        change(&current)
        store(current)
    }

    private func store(_ new: WatchDay) {
        day = new
        if let data = try? JSONEncoder().encode(new) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
    }

    /// Message direct si l'iPhone est joignable, sinon file d'attente livrée plus tard.
    private func send(_ action: WatchAction) {
        guard let session else { return }
        if session.isReachable {
            session.sendMessage(action.encoded(), replyHandler: nil) { _ in session.transferUserInfo(action.encoded()) }
        } else {
            session.transferUserInfo(action.encoded())
        }
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        guard let day = WatchDay.decode(session.receivedApplicationContext) else { return }
        Task { @MainActor in self.store(day) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let day = WatchDay.decode(context) else { return }
        Task { @MainActor in self.store(day) }
    }
}
