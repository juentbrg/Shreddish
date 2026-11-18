import Foundation

/// Fenêtre de repas d'un jeûne intermittent (spec 015), en minutes depuis minuit, sur une même journée.
public struct EatingWindow: Sendable, Equatable {
    /// Écart minimal entre premier et dernier repas.
    public static let minimumMinutes = 4 * 60
    public static let `default` = EatingWindow(startMinutes: 12 * 60, endMinutes: 19 * 60 + 30)

    public var startMinutes: Int
    public var endMinutes: Int

    public init(startMinutes: Int, endMinutes: Int) {
        let start = min(max(startMinutes, 0), 24 * 60 - 1 - Self.minimumMinutes)
        self.startMinutes = start
        self.endMinutes = min(max(endMinutes, start + Self.minimumMinutes), 24 * 60 - 1)
    }

    /// Heures de jeûne, du dernier repas au premier du lendemain.
    public var fastingMinutes: Int { 24 * 60 - (endMinutes - startMinutes) }

    /// « 12:00-19:30 », tel qu'envoyé à l'IA.
    public var label: String { "\(Self.clock(startMinutes))-\(Self.clock(endMinutes))" }

    public func contains(_ minutes: Int) -> Bool { (startMinutes...endMinutes).contains(minutes) }

    /// Heures des repas d'une journée ramenées dans la fenêtre. Inchangées si toutes y sont déjà ;
    /// sinon réparties à intervalles réguliers (au quart d'heure), dans l'ordre des heures proposées.
    public func fit(_ meals: [MealDTO]) -> [MealDTO] {
        let times = meals.map { SupplementPlacement.minutes($0.time) }
        if times.allSatisfy({ $0.map(contains) ?? false }) { return meals }
        let order = meals.indices.sorted { lhs, rhs in
            (times[lhs] ?? Int.max, lhs) < (times[rhs] ?? Int.max, rhs)
        }
        var fitted = meals
        let span = endMinutes - startMinutes
        for (rank, index) in order.enumerated() {
            let offset = order.count > 1 ? span * rank / (order.count - 1) : 0
            let quarter = min((startMinutes + offset) / 15 * 15, endMinutes)
            fitted[index].time = Self.clock(max(quarter, startMinutes))
        }
        return fitted
    }

    /// Heure d'un repas seul (remplacement) ramenée dans la fenêtre.
    public func fit(time: String?) -> String? {
        guard let minutes = SupplementPlacement.minutes(time) else { return time }
        return Self.clock(min(max(minutes, startMinutes), endMinutes))
    }

    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60 % 24, minutes % 60) }
}
