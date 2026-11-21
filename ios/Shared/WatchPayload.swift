import Foundation

/// Données de la journée envoyées par l'iPhone à l'Apple Watch (spec 017, FR-1711), via WatchConnectivity.
struct WatchDay: Codable, Equatable, Sendable {
    struct Meal: Codable, Equatable, Sendable, Identifiable {
        var dayKey: Int
        var order: Int
        var time: String?
        var typeLabel: String
        var name: String
        var kcal: Int
        var proteinG: Int
        /// planned, eaten, skipped.
        var status: String
        var id: String { "\(dayKey)-\(order)" }
    }

    var dayKey: Int
    var meals: [Meal]
    var targetKcal: Int
    var targetProteinG: Int
    var eatenKcal: Int
    var eatenProteinG: Int
    var lastWeightKg: Double?
    var weighedToday: Bool
    var updatedAt: Date

    static let contextKey = "watchDay"

    func encoded() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [Self.contextKey: data]
    }

    static func decode(_ context: [String: Any]) -> WatchDay? {
        guard let data = context[contextKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchDay.self, from: data)
    }
}

/// Action faite sur la montre, appliquée par l'iPhone.
enum WatchAction: Codable, Equatable, Sendable {
    case mealStatus(dayKey: Int, order: Int, status: String)
    case weight(kg: Double)

    static let key = "watchAction"

    func encoded() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [Self.key: data]
    }

    static func decode(_ message: [String: Any]) -> WatchAction? {
        guard let data = message[key] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchAction.self, from: data)
    }
}
