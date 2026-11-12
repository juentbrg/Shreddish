import Foundation
import SwiftData
import Testing
@testable import ShreddishCore

struct EnergyCalibrationTests {
    static let today = LocalDay(year: 2026, month: 12, day: 1)

    static func intakes(days: Int, kcal: Double, complete: Bool = true, endingDaysAgo: Int = 1) -> [DayIntake] {
        (0..<days).map { DayIntake(day: today.adding(days: -endingDaysAgo - $0), kcal: kcal, isComplete: complete) }
    }

    /// Pesées linéaires de `from` à `to` sur `span` jours, se terminant aujourd'hui.
    static func weights(from: Double, to: Double, span: Int, every step: Int = 1) -> [WeightPoint] {
        stride(from: 0, through: span, by: step).map { offset in
            WeightPoint(day: today.adding(days: offset - span), weightKg: from + (to - from) * Double(offset) / Double(span))
        }
    }

    @Test func estimatesRealExpenditure() throws {
        let outcome = EnergyCalibration.estimate(
            intakes: Self.intakes(days: 14, kcal: 2000), weights: Self.weights(from: 80, to: 79, span: 14),
            formulaTdee: 2273, today: Self.today
        )
        guard case let .estimate(estimate) = outcome else { Issue.record("\(outcome)"); return }
        #expect(abs(estimate.observedTdee - 2550) < 0.5) // 2000 + 1/14 × 7700
        #expect(abs(estimate.weeklyChangeKg + 0.5) < 0.001)
        #expect(estimate.completeDays == 14)
        #expect(abs(estimate.averageIntake - 2000) < 0.001)
    }

    @Test func regressionIgnoresNoise() throws {
        var points = Self.weights(from: 80, to: 79, span: 14)
        points[3].weightKg += 0.6
        points[4].weightKg -= 0.6
        let outcome = EnergyCalibration.estimate(
            intakes: Self.intakes(days: 14, kcal: 2000), weights: points, formulaTdee: 2273, today: Self.today
        )
        guard case let .estimate(estimate) = outcome else { Issue.record("\(outcome)"); return }
        #expect(abs(estimate.observedTdee - 2550) < 60)
    }

    @Test func incompleteDaysAreIgnored() {
        let intakes = Self.intakes(days: 9, kcal: 2000) + Self.intakes(days: 10, kcal: 500, complete: false, endingDaysAgo: 10)
        let outcome = EnergyCalibration.estimate(
            intakes: intakes, weights: Self.weights(from: 80, to: 79, span: 14), formulaTdee: 2273, today: Self.today
        )
        #expect(outcome == .insufficientData(completeDays: 9, weightSpanDays: 14))
    }

    @Test func todayAndOldDaysAreOutsideTheWindow() {
        let intakes = Self.intakes(days: 1, kcal: 2000, endingDaysAgo: 0)
            + Self.intakes(days: 12, kcal: 2000, endingDaysAgo: 29)
        let outcome = EnergyCalibration.estimate(
            intakes: intakes, weights: Self.weights(from: 80, to: 79, span: 14), formulaTdee: 2273, today: Self.today
        )
        #expect(outcome == .insufficientData(completeDays: 0, weightSpanDays: 14))
    }

    @Test func weightsMustCoverTwoWeeks() {
        let outcome = EnergyCalibration.estimate(
            intakes: Self.intakes(days: 14, kcal: 2000), weights: Self.weights(from: 80, to: 79.5, span: 10),
            formulaTdee: 2273, today: Self.today
        )
        #expect(outcome == .insufficientData(completeDays: 14, weightSpanDays: 10))
    }

    @Test func aberrantEstimateIsRejected() {
        // 800 kcal par jour journalisées pour une perte de 0,5 kg / semaine : journal incomplet.
        let outcome = EnergyCalibration.estimate(
            intakes: Self.intakes(days: 14, kcal: 800), weights: Self.weights(from: 80, to: 79, span: 14),
            formulaTdee: 2273, today: Self.today
        )
        guard case let .implausible(observed) = outcome else { Issue.record("\(outcome)"); return }
        #expect(abs(observed - 1350) < 0.5)
    }

    @Test func adjustmentMovesHalfway() {
        let first = EnergyCalibration.nextAdjustment(current: 0, formulaTdee: 2273, observedTdee: 2550)
        #expect(abs(first - 138.5) < 0.001)
        let second = EnergyCalibration.nextAdjustment(current: first, formulaTdee: 2273, observedTdee: 2550)
        #expect(abs(second - 207.75) < 0.001)
    }

    @Test func adjustmentStepIsCapped() {
        #expect(EnergyCalibration.nextAdjustment(current: 0, formulaTdee: 2000, observedTdee: 3000) == 150)
        #expect(EnergyCalibration.nextAdjustment(current: 0, formulaTdee: 3000, observedTdee: 2000) == -150)
    }

    @Test func adjustmentTotalIsCapped() {
        #expect(EnergyCalibration.nextAdjustment(current: 550, formulaTdee: 2000, observedTdee: 3000) == 600)
    }

    @MainActor
    @Test func intakesFromPlansKeepBestLoggedDay() throws {
        let container = try ShreddishStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let targets = try NutritionCalculator.targets(for: NutritionCalculatorTests.man)
        let start = LocalDay(year: 2026, month: 11, day: 11)
        let old = try PlanStore.saveWeek(try Fixture.week(), startDay: start, targets: targets, createdAt: .now, in: context)
        let new = try PlanStore.saveWeek(
            try Fixture.week(), startDay: start.adding(days: 3), targets: targets, createdAt: .now.addingTimeInterval(1), in: context
        )
        // Ancien planning, jour 3 : tout journalisé. Nouveau planning, même jour : rien.
        for meal in old.sortedDays[3].meals { meal.setStatus(.eaten, at: .now) }
        // Jour 0 de l'ancien planning : partiel.
        old.sortedDays[0].sortedMeals[0].setStatus(.eaten, at: .now)
        _ = new

        let intakes = EnergyCalibration.intakes(from: old.days + new.days)
        let day3 = try #require(intakes.first { $0.day == start.adding(days: 3) })
        #expect(day3.isComplete)
        #expect(day3.kcal == 2208)
        #expect(intakes.first { $0.day == start }?.isComplete == false)
        #expect(Set(intakes.map(\.day)).count == intakes.count)
    }
}
