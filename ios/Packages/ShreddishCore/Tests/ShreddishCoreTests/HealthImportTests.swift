import Foundation
import Testing
@testable import ShreddishCore

/// Apple Santé (spec 017, FR-1709).
struct HealthImportTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    @Test func keepsTheLatestWeighInOfDaysWithoutEntry() {
        let samples = [(date: date(18, 7), kg: 81.04), (date: date(18, 21), kg: 81.9), (date: date(19, 7), kg: 80.8),
                       (date: date(20, 7), kg: 300.0)]
        let existing: Set<LocalDay> = [LocalDay(year: 2026, month: 11, day: 19)]
        let points = HealthImport.newWeights(samples: samples, existing: existing, calendar: calendar)
        #expect(points == [WeightPoint(day: LocalDay(year: 2026, month: 11, day: 18), weightKg: 81.9)])
    }

    @Test func syncIdentifierIsStablePerDayAndNutrient() {
        let day = LocalDay(year: 2026, month: 11, day: 20)
        #expect(HealthImport.syncIdentifier(day: day, nutrient: "kcal") == "shreddish-20261120-kcal")
    }
}
