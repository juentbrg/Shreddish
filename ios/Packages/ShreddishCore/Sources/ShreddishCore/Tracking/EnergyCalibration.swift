import Foundation

/// Apport d'un jour d'après le journal (FR-105).
public struct DayIntake: Sendable, Equatable {
    public var day: LocalDay
    public var kcal: Double
    /// Au moins un repas et aucun repas encore « prévu ».
    public var isComplete: Bool

    public init(day: LocalDay, kcal: Double, isComplete: Bool) {
        self.day = day
        self.kcal = kcal
        self.isComplete = isComplete
    }
}

public struct EnergyEstimate: Sendable, Equatable {
    /// Dépense réelle estimée, kcal / jour.
    public var observedTdee: Double
    public var averageIntake: Double
    /// Variation de poids par semaine (négative = perte).
    public var weeklyChangeKg: Double
    public var completeDays: Int
    public var weightSpanDays: Int
}

public enum CalibrationOutcome: Sendable, Equatable {
    case estimate(EnergyEstimate)
    case insufficientData(completeDays: Int, weightSpanDays: Int)
    /// Hors [60 %, 150 %] de la formule : journal probablement incomplet (FR-107).
    case implausible(observedTdee: Double)
}

/// Dépense réelle d'après pesées et journal, et ajustement hebdomadaire (US2, spec 002).
public enum EnergyCalibration {
    public static let windowDays = 28
    public static let requiredCompleteDays = 10
    public static let requiredWeightSpanDays = 14
    public static let kcalPerKg = 7700.0
    public static let plausibleRange = 0.6...1.5
    public static let maxWeeklyStep = 150.0
    public static let minimumDaysBetweenAdjustments = 7

    /// Apports journaliers depuis les jours de planning ; un jour couvert par plusieurs plannings
    /// garde la version la plus renseignée.
    @MainActor
    public static func intakes(from days: [DayPlan]) -> [DayIntake] {
        var best: [Int: (logged: Int, day: DayPlan)] = [:]
        for day in days {
            let logged = day.meals.filter { $0.status != .planned }.count + day.extras.count
            if let current = best[day.dayKey], current.logged >= logged { continue }
            best[day.dayKey] = (logged, day)
        }
        return best.values
            .map { entry in
                let day = entry.day
                let complete = !day.meals.isEmpty && day.meals.allSatisfy { $0.status != .planned }
                return DayIntake(day: day.day, kcal: day.actualTotals.kcal, isComplete: complete)
            }
            .sorted { $0.day < $1.day }
    }

    /// Estimation sur les 28 derniers jours : apport sur [J−28, J−1], pesées sur [J−28, J].
    public static func estimate(
        intakes: [DayIntake], weights: [WeightPoint], formulaTdee: Double, today: LocalDay
    ) -> CalibrationOutcome {
        let start = today.adding(days: -windowDays)
        let complete = intakes.filter { $0.isComplete && $0.day >= start && $0.day < today }
        let points = weights.filter { $0.day >= start && $0.day <= today }.sorted { $0.day < $1.day }
        let span = points.count >= 2 ? points[points.count - 1].day.days(since: points[0].day) : 0

        guard complete.count >= requiredCompleteDays, span >= requiredWeightSpanDays,
              let slope = slopePerDay(points) else {
            return .insufficientData(completeDays: complete.count, weightSpanDays: span)
        }
        let averageIntake = complete.reduce(0) { $0 + $1.kcal } / Double(complete.count)
        let observed = averageIntake - slope * kcalPerKg
        guard formulaTdee > 0, plausibleRange.contains(observed / formulaTdee) else {
            return .implausible(observedTdee: observed)
        }
        return .estimate(EnergyEstimate(
            observedTdee: observed, averageIntake: averageIntake, weeklyChangeKg: slope * 7,
            completeDays: complete.count, weightSpanDays: span
        ))
    }

    /// Ajustement suivant : moitié de l'écart restant, pas de ±150 kcal, total de ±600 kcal (FR-108).
    public static func nextAdjustment(current: Double, formulaTdee: Double, observedTdee: Double) -> Double {
        let target = observedTdee - formulaTdee
        let step = min(max((target - current) / 2, -maxWeeklyStep), maxWeeklyStep)
        let limit = NutritionCalculator.maxTdeeAdjustment
        return min(max(current + step, -limit), limit)
    }

    /// Pente du poids en kg / jour, régression linéaire des moindres carrés.
    static func slopePerDay(_ points: [WeightPoint]) -> Double? {
        guard points.count >= 2, let first = points.first?.day else { return nil }
        let xs = points.map { Double($0.day.days(since: first)) }
        let ys = points.map(\.weightKg)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        let numerator = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let denominator = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        return denominator > 0 ? numerator / denominator : nil
    }
}
