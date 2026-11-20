import Foundation

/// Échanges avec Apple Santé (spec 017, FR-1709), logique sans HealthKit.
public enum HealthImport {
    /// Pesées Santé à importer : la dernière de chaque jour, seulement les jours sans pesée dans l'app.
    public static func newWeights(
        samples: [(date: Date, kg: Double)], existing: Set<LocalDay>, calendar: Calendar
    ) -> [WeightPoint] {
        var latest: [LocalDay: (date: Date, kg: Double)] = [:]
        for sample in samples where NutritionCalculator.weightRange.contains(sample.kg) {
            let day = LocalDay(date: sample.date, calendar: calendar)
            guard !existing.contains(day) else { continue }
            if let current = latest[day], current.date >= sample.date { continue }
            latest[day] = sample
        }
        return latest.map { WeightPoint(day: $0.key, weightKg: ($0.value.kg * 10).rounded() / 10) }.sorted { $0.day < $1.day }
    }

    /// Identifiant de synchro d'un total journalier : Santé remplace l'ancienne valeur du même jour.
    public static func syncIdentifier(day: LocalDay, nutrient: String) -> String { "shreddish-\(day.key)-\(nutrient)" }
}
