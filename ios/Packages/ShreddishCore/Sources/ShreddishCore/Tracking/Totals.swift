import Foundation

public struct LoggedMeal: Sendable, Equatable {
    public var macros: MacroTotals
    public var status: MealStatus

    public init(macros: MacroTotals, status: MealStatus) {
        self.macros = macros
        self.status = status
    }
}

/// Journal d'un jour : repas du planning avec statut + extras (FR-018).
public struct DayLog: Sendable, Equatable {
    public var day: LocalDay
    public var meals: [LoggedMeal]
    public var extras: [MacroTotals]

    public init(day: LocalDay, meals: [LoggedMeal], extras: [MacroTotals]) {
        self.day = day
        self.meals = meals
        self.extras = extras
    }
}

/// Bilan hebdomadaire (FR-018b).
public struct WeeklySummary: Sendable, Equatable {
    /// Jours écoulés pris en compte (jour courant seulement après 21 h).
    public var elapsedDays: Int
    public var averageActual: MacroTotals
    public var eatenCount: Int
    public var plannedCount: Int
    /// Repas mangés / repas des jours écoulés ; `nil` sans jour écoulé.
    public var adherenceRate: Double?
}

public enum Totals {
    /// Seuil d'écart à la cible au-delà duquel un jour est signalé (FR-011).
    public static let offTargetThreshold = 0.10
    /// Heure à partir de laquelle le jour courant compte dans le bilan.
    public static let dayClosingMinute = 21 * 60

    public static func planned(_ meals: [MealDTO]) -> MacroTotals {
        meals.map(\.macros).sum()
    }

    /// Réel : repas `eaten` + extras ; `planned` et `skipped` non comptés.
    public static func actual(_ log: DayLog) -> MacroTotals {
        log.meals.filter { $0.status == .eaten }.map(\.macros).sum() + log.extras.sum()
    }

    /// Écart signé à la cible (0,1 = 10 % au-dessus).
    public static func deviation(_ totals: MacroTotals, targetKcal: Double) -> Double {
        guard targetKcal > 0 else { return 0 }
        return (totals.kcal - targetKcal) / targetKcal
    }

    public static func isOffTarget(_ deviation: Double) -> Bool {
        abs(deviation) > offTargetThreshold + 1e-9
    }

    public static func weeklySummary(days: [DayLog], clock: any AppClock) -> WeeklySummary {
        let today = clock.today
        let todayClosed = clock.minuteOfDay >= dayClosingMinute
        let elapsed = days.filter { $0.day < today || ($0.day == today && todayClosed) }

        let eaten = elapsed.reduce(0) { $0 + $1.meals.filter { $0.status == .eaten }.count }
        let planned = elapsed.reduce(0) { $0 + $1.meals.count }
        let total = elapsed.map(actual).sum()
        let count = Double(elapsed.count)
        let average = elapsed.isEmpty ? MacroTotals.zero : MacroTotals(
            kcal: total.kcal / count, proteinG: total.proteinG / count,
            carbsG: total.carbsG / count, fatG: total.fatG / count
        )
        return WeeklySummary(
            elapsedDays: elapsed.count,
            averageActual: average,
            eatenCount: eaten,
            plannedCount: planned,
            adherenceRate: planned > 0 ? Double(eaten) / Double(planned) : nil
        )
    }
}
