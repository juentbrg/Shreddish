import Foundation
import SwiftData
import Testing
@testable import ShreddishCore

/// Suivi des progrès (spec 017, FR-1708).
struct ProgressTests {
    let today = LocalDay(year: 2026, month: 11, day: 20)

    @Test func monthlyReportSummarizesTheLast30Days() {
        let weights = [
            WeightPoint(day: today.adding(days: -40), weightKg: 85),
            WeightPoint(day: today.adding(days: -28), weightKg: 82),
            WeightPoint(day: today, weightKg: 80.5),
        ]
        let measures: [(day: LocalDay, waist: Double?)] = [(today.adding(days: -20), 90), (today, 87.5)]
        let meals: [(day: LocalDay, status: MealStatus)] = [
            (today, .eaten), (today, .eaten), (today, .skipped), (today.adding(days: -1), .planned),
        ]
        let report = MonthlyReport.make(today: today, weights: weights, measurements: measures, meals: meals)
        #expect(report.weightChange == -1.5)
        #expect(report.waistChange == -2.5)
        #expect(report.adherence == 0.5)
        #expect(report.weighIns == 2)
    }

    @Test func singleWeighInHasNoChange() {
        let report = MonthlyReport.make(today: today, weights: [WeightPoint(day: today, weightKg: 80)], measurements: [], meals: [])
        #expect(report.weightChange == nil)
        #expect(report.adherence == nil)
    }

    @MainActor @Test func measurementsAndPhotosArePersisted() throws {
        let container = try ShreddishStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let entry = BodyMeasurement(day: today, recordedAt: .now)
        #expect(entry.isEmpty)
        entry.waistCm = 88
        context.insert(entry)
        context.insert(ProgressPhoto(day: today, pose: "front", imageData: Data([1, 2, 3]), createdAt: .now))
        try context.save()
        #expect(try context.fetch(FetchDescriptor<BodyMeasurement>()).first?.waistCm == 88)
        #expect(try context.fetch(FetchDescriptor<ProgressPhoto>()).first?.imageData == Data([1, 2, 3]))
    }
}
