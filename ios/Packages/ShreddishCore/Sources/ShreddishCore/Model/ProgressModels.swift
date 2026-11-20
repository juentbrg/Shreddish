import Foundation
import SwiftData

/// Mensurations d'un jour, en cm (spec 017, FR-1708). Prêt pour CloudKit.
@Model
public final class BodyMeasurement {
    public var id = UUID()
    public var dayKey = 0
    public var waistCm: Double?
    public var hipsCm: Double?
    public var chestCm: Double?
    public var armCm: Double?
    public var thighCm: Double?
    public var recordedAt = Date()

    public init(day: LocalDay, recordedAt: Date) {
        dayKey = day.key
        self.recordedAt = recordedAt
    }

    public var day: LocalDay { LocalDay(key: dayKey) }
    public var isEmpty: Bool { [waistCm, hipsCm, chestCm, armCm, thighCm].allSatisfy { $0 == nil } }
}

/// Photo de progrès privée : sur l'appareil (et iCloud plus tard), jamais envoyée à l'IA (FR-1708).
@Model
public final class ProgressPhoto {
    public var id = UUID()
    public var dayKey = 0
    /// Face, profil, dos.
    public var poseRaw = "front"
    @Attribute(.externalStorage) public var imageData: Data?
    public var createdAt = Date()

    public init(day: LocalDay, pose: String, imageData: Data, createdAt: Date) {
        dayKey = day.key
        poseRaw = pose
        self.imageData = imageData
        self.createdAt = createdAt
    }

    public var day: LocalDay { LocalDay(key: dayKey) }
}

/// Bilan d'un mois : poids, tour de taille, adhérence au plan.
public struct MonthlyReport: Equatable, Sendable {
    public var firstWeight: Double?
    public var lastWeight: Double?
    public var waistChange: Double?
    /// Repas cochés « mangé » ÷ repas prévus jusqu'à aujourd'hui.
    public var adherence: Double?
    public var mealsEaten: Int
    public var mealsPlanned: Int
    public var weighIns: Int

    public var weightChange: Double? {
        guard let firstWeight, let lastWeight else { return nil }
        return lastWeight - firstWeight
    }

    /// Bilan des 30 derniers jours jusqu'à `today` inclus.
    public static func make(
        today: LocalDay, weights: [WeightPoint], measurements: [(day: LocalDay, waist: Double?)],
        meals: [(day: LocalDay, status: MealStatus)]
    ) -> MonthlyReport {
        let start = today.adding(days: -29)
        let inRange: (LocalDay) -> Bool = { start <= $0 && $0 <= today }
        let monthWeights = weights.filter { inRange($0.day) }.sorted { $0.day < $1.day }
        let waists = measurements.filter { inRange($0.day) }.sorted { $0.day < $1.day }.compactMap(\.waist)
        let pastMeals = meals.filter { inRange($0.day) }
        let eaten = pastMeals.filter { $0.status == .eaten }.count
        return MonthlyReport(
            firstWeight: monthWeights.first?.weightKg, lastWeight: monthWeights.count > 1 ? monthWeights.last?.weightKg : nil,
            waistChange: waists.count > 1 ? waists.last! - waists.first! : nil,
            adherence: pastMeals.isEmpty ? nil : Double(eaten) / Double(pastMeals.count),
            mealsEaten: eaten, mealsPlanned: pastMeals.count, weighIns: monthWeights.count
        )
    }
}
