import Foundation
import ShreddishCore
import SwiftData

/// Calibration de la dépense par pesées + journal (spec 002, US2).
@MainActor
enum CalibrationService {
    /// Dépense selon la formule, sans ajustement de calibration.
    static func formulaTdee(profile: Profile, clock: any AppClock) -> Double? {
        var input = profile.input(clock: clock)
        input.tdeeAdjustmentKcal = 0
        do {
            try NutritionCalculator.validate(input)
        } catch {
            return nil
        }
        return NutritionCalculator.formulaTdee(input)
    }

    static func outcome(profile: Profile, context: ModelContext, clock: any AppClock) -> CalibrationOutcome? {
        guard let formula = formulaTdee(profile: profile, clock: clock) else { return nil }
        let days = (try? context.fetch(FetchDescriptor<DayPlan>())) ?? []
        let weights = ((try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []).map(\.point)
        return EnergyCalibration.estimate(
            intakes: EnergyCalibration.intakes(from: days), weights: weights, formulaTdee: formula, today: clock.today
        )
    }

    /// Ajustement automatique dû : actif et au moins 7 jours depuis le dernier (FR-108, FR-109).
    static func isDue(profile: Profile, clock: any AppClock) -> Bool {
        guard profile.isAutoCalibrationOn else { return false }
        guard let last = profile.lastCalibrationAt else { return true }
        let days = LocalDay(date: clock.now, calendar: clock.calendar)
            .days(since: LocalDay(date: last, calendar: clock.calendar))
        return days >= EnergyCalibration.minimumDaysBetweenAdjustments
    }

    /// Applique un pas d'ajustement et renvoie le message à afficher.
    static func apply(_ estimate: EnergyEstimate, to profile: Profile, clock: any AppClock) -> String? {
        guard let formula = formulaTdee(profile: profile, clock: clock) else { return nil }
        let before = profile.targets(clock: clock)?.targetKcal
        profile.tdeeAdjustmentKcal = EnergyCalibration.nextAdjustment(
            current: profile.tdeeAdjustmentKcal ?? 0, formulaTdee: formula, observedTdee: estimate.observedTdee
        )
        profile.lastCalibrationAt = clock.now
        let after = profile.targets(clock: clock)?.targetKcal
        guard let before, let after else { return nil }
        if before == after {
            return "Tes pesées confirment ta cible : \(Format.kcal(Double(after)))."
        }
        return "Cibles ajustées d'après tes pesées : \(Format.kcal(Double(before))) → \(Format.kcal(Double(after)))."
    }
}

extension AppModel {
    /// À l'ouverture et au retour au premier plan : ajustement hebdomadaire si dû et possible.
    func calibrateIfDue(context: ModelContext) {
        guard let profile = try? context.fetch(FetchDescriptor<Profile>()).first,
              profile.disclaimerAcceptedAt != nil,
              CalibrationService.isDue(profile: profile, clock: clock),
              case let .estimate(estimate) = CalibrationService.outcome(profile: profile, context: context, clock: clock)
        else { return }
        calibrationMessage = CalibrationService.apply(estimate, to: profile, clock: clock)
        try? context.save()
    }
}
