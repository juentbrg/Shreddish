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

    /// Jour à régénérer après ajustement des portions (spec 010) : kcal à plus de 10 %, protéines sous 90 %,
    /// ou glucides ou lipides à plus de 25 %.
    public static func needsRegeneration(_ totals: MacroTotals, targets: MacroTotals) -> Bool {
        func far(_ value: Double, _ target: Double) -> Bool { target > 0 && abs(value - target) / target > 0.25 }
        return isOffTarget(deviation(totals, targetKcal: targets.kcal)) || totals.proteinG < 0.9 * targets.proteinG
            || far(totals.carbsG, targets.carbsG) || far(totals.fatG, targets.fatG)
    }

    /// Écart relatif cumulé (kcal, protéines, glucides, lipides) : comparer deux propositions.
    public static func targetDistance(_ totals: MacroTotals, targets: MacroTotals) -> Double {
        let pairs = [(totals.kcal, targets.kcal), (totals.proteinG, targets.proteinG),
                     (totals.carbsG, targets.carbsG), (totals.fatG, targets.fatG)]
        return pairs.reduce(0) { $0 + ($1.1 > 0 ? abs($1.0 - $1.1) / $1.1 : 0) }
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
