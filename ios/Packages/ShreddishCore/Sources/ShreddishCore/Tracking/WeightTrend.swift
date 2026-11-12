import Foundation

public struct WeightPoint: Sendable, Equatable {
    public var day: LocalDay
    public var weightKg: Double

    public init(day: LocalDay, weightKg: Double) {
        self.day = day
        self.weightKg = weightKg
    }
}

/// Rythme de perte de poids (US6).
public enum WeightTrend {
    /// Perte max conseillée en sèche, en % du poids par semaine.
    public static let maxWeeklyLossPercent = 1.0
    static let minimumSpanDays = 14

    /// Perte en % du poids par semaine (positive = perte) entre la dernière pesée et la pesée la plus
    /// proche d'au moins 14 jours avant. `nil` si l'historique couvre moins de 2 semaines.
    public static func weeklyLossRate(_ entries: [WeightPoint]) -> Double? {
        let sorted = entries.sorted { $0.day < $1.day }
        guard let latest = sorted.last else { return nil }
        guard let reference = sorted.last(where: { latest.day.days(since: $0.day) >= minimumSpanDays }),
              reference.weightKg > 0 else { return nil }
        let weeks = Double(latest.day.days(since: reference.day)) / 7
        return (reference.weightKg - latest.weightKg) / reference.weightKg * 100 / weeks
    }

    public static func isTooFast(_ entries: [WeightPoint], goal: Goal) -> Bool {
        guard goal == .cut, let rate = weeklyLossRate(entries) else { return false }
        return rate > maxWeeklyLossPercent + 1e-9
    }
}
