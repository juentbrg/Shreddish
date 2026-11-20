import Foundation
import HealthKit
import Observation
import ShreddishCore
import SwiftData

/// Apple Santé (spec 017, FR-1709), désactivé par défaut : pesées importées, dépense active lue,
/// apports du journal écrits (un total par jour, remplacé à chaque synchro).
@MainActor
@Observable
final class HealthService {
    static let enabledKey = "healthEnabled"

    private let store: HKHealthStore?
    private let defaults: UserDefaults
    /// Dépense active moyenne des 14 derniers jours, en kcal.
    private(set) var averageActiveKcal: Double?
    private(set) var lastError: String?

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    init(enabled: Bool, defaults: UserDefaults = .standard) {
        store = enabled && HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
        self.defaults = defaults
        isEnabled = enabled && defaults.bool(forKey: Self.enabledKey)
    }

    var isAvailable: Bool { store != nil }

    private static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.bodyMass), HKQuantityType(.activeEnergyBurned),
    ]
    /// Apport écrit dans Santé : type, clé de synchro, unité, valeur tirée des totaux du jour.
    private struct Nutrient {
        let id: HKQuantityTypeIdentifier
        let key: String
        let unit: HKUnit
        let value: (MacroTotals) -> Double
    }

    private static let nutrients = [
        Nutrient(id: .dietaryEnergyConsumed, key: "kcal", unit: .kilocalorie(), value: \.kcal),
        Nutrient(id: .dietaryProtein, key: "protein", unit: .gram(), value: \.proteinG),
        Nutrient(id: .dietaryCarbohydrates, key: "carbs", unit: .gram(), value: \.carbsG),
        Nutrient(id: .dietaryFatTotal, key: "fat", unit: .gram(), value: \.fatG),
    ]

    /// Active Santé : autorisations demandées, puis première synchro.
    func enable(container: ModelContainer, clock: any AppClock) async {
        guard let store else { return }
        let share = Set(Self.nutrients.map { HKQuantityType($0.id) })
        do {
            try await store.requestAuthorization(toShare: share, read: Self.readTypes)
            isEnabled = true
            await sync(container: container, clock: clock)
        } catch {
            lastError = String(localized: "Autorisation Santé refusée.")
        }
    }

    func disable() {
        isEnabled = false
        averageActiveKcal = nil
    }

    /// Pesées importées, dépense active lue, apports des 7 derniers jours écrits.
    func sync(container: ModelContainer, clock: any AppClock) async {
        guard isEnabled, let store else { return }
        let context = container.mainContext
        await importWeights(store: store, context: context, clock: clock)
        averageActiveKcal = await activeEnergy(store: store, clock: clock)
        await exportIntake(store: store, context: context, clock: clock)
    }

    private func importWeights(store: HKHealthStore, context: ModelContext, clock: any AppClock) async {
        let since = clock.calendar.date(byAdding: .day, value: -60, to: clock.now) ?? clock.now
        let samples = await quantitySamples(.bodyMass, since: since, store: store)
            .filter { $0.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier }
            .map { (date: $0.endDate, kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
        let existing = Set(((try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []).map(\.day))
        let points = HealthImport.newWeights(samples: samples, existing: existing, calendar: clock.calendar)
        for point in points {
            context.insert(WeightEntry(day: point.day, weightKg: point.weightKg, recordedAt: clock.now))
        }
        if !points.isEmpty { try? context.save() }
    }

    private func activeEnergy(store: HKHealthStore, clock: any AppClock) async -> Double? {
        let start = clock.calendar.startOfDay(for: clock.calendar.date(byAdding: .day, value: -14, to: clock.now) ?? clock.now)
        let end = clock.calendar.startOfDay(for: clock.now)
        let total = await quantitySamples(.activeEnergyBurned, since: start, store: store)
            .filter { $0.endDate <= end }
            .reduce(0) { $0 + $1.quantity.doubleValue(for: .kilocalorie()) }
        return total > 0 ? total / 14 : nil
    }

    private func exportIntake(store: HKHealthStore, context: ModelContext, clock: any AppClock) async {
        let today = clock.today
        let days = PlanStore.activePlans(in: context).flatMap(\.days)
            .filter { $0.day <= today && $0.day >= today.adding(days: -6) }
        var samples: [HKQuantitySample] = []
        let version = Int(clock.now.timeIntervalSince1970)
        for day in days {
            let totals = day.actualTotals
            guard totals.kcal > 0 else { continue }
            let start = day.day.startDate(calendar: clock.calendar)
            let end = min(clock.now, clock.calendar.date(byAdding: .day, value: 1, to: start) ?? start)
            for nutrient in Self.nutrients {
                let metadata: [String: Any] = [
                    HKMetadataKeySyncIdentifier: HealthImport.syncIdentifier(day: day.day, nutrient: nutrient.key),
                    HKMetadataKeySyncVersion: version,
                ]
                samples.append(HKQuantitySample(
                    type: HKQuantityType(nutrient.id), quantity: HKQuantity(unit: nutrient.unit, doubleValue: nutrient.value(totals)),
                    start: start, end: max(start, end), metadata: metadata
                ))
            }
        }
        guard !samples.isEmpty else { return }
        do { try await store.save(samples) } catch { lastError = String(localized: "Écriture dans Santé impossible.") }
    }

    private func quantitySamples(
        _ identifier: HKQuantityTypeIdentifier, since start: Date, store: HKHealthStore
    ) async -> [HKQuantitySample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: HKQuery.predicateForSamples(
                withStart: start, end: nil
            ))],
            sortDescriptors: [SortDescriptor(\.endDate)]
        )
        return (try? await descriptor.result(for: store)) ?? []
    }
}
