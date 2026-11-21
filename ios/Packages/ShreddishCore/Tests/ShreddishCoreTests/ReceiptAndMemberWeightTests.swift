import Foundation
import SwiftData
import Testing
@testable import ShreddishCore

/// Ticket réel (FR-1718) et pesées des membres du foyer (FR-1704).
@MainActor
struct ReceiptAndMemberWeightTests {
    typealias FixedClock = HouseholdTests.FixedClock

    @Test func receiptIsRecordedThenReplaced() throws {
        let container = try ShreddishStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let planID = UUID()
        ShoppingReceipt.record(52.4, planID: planID, at: .now, in: context)
        ShoppingReceipt.record(49.9, planID: planID, at: .now, in: context)
        #expect(try context.fetch(FetchDescriptor<ShoppingReceipt>()).count == 1)
        #expect(ShoppingReceipt.find(planID: planID, in: context)?.amountEUR == 49.9)
        #expect(ShoppingReceipt.find(planID: UUID(), in: context) == nil)
    }

    @Test func receiptRejectsAbsurdAmounts() throws {
        let container = try ShreddishStore.makeContainer(inMemory: true)
        #expect(ShoppingReceipt.record(0, planID: UUID(), at: .now, in: container.mainContext) == nil)
        #expect(ShoppingReceipt.record(5000, planID: UUID(), at: .now, in: container.mainContext) == nil)
    }

    @Test func comparisonGivesGapAndBudget() {
        let cheaper = ReceiptComparison(estimatedEUR: 60, paidEUR: 54, budgetEUR: 56)
        #expect(cheaper.difference == -6)
        #expect(cheaper.relativeDifference == -0.1)
        #expect(cheaper.withinBudget)
        #expect(!ReceiptComparison(estimatedEUR: 50, paidEUR: 58, budgetEUR: 56).withinBudget)
        #expect(ReceiptComparison(estimatedEUR: 0, paidEUR: 10, budgetEUR: 0).relativeDifference == nil)
    }

    @Test func memberWeighInUpdatesProfileAndPortion() throws {
        let container = try ShreddishStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let clock = FixedClock()
        let member = HouseholdMember(name: "Léa")
        member.sexRaw = Sex.female.rawValue
        member.birthDate = clock.calendar.date(byAdding: .year, value: -30, to: clock.now)
        member.heightCm = 165
        member.weightKg = 70
        member.activityRaw = ActivityLevel.moderate.rawValue
        member.goalRaw = Goal.recomp.rawValue
        context.insert(member)
        member.refreshPortion(mainKcal: 2400, clock: clock)
        let before = member.portion

        MemberWeight.record(60, for: member, mainKcal: 2400, clock: clock, in: context)
        MemberWeight.record(59.5, for: member, mainKcal: 2400, clock: clock, in: context)

        let history = MemberWeight.history(of: member.id, in: context)
        #expect(history.count == 1)
        #expect(history.first?.weightKg == 59.5)
        #expect(member.weightKg == 59.5)
        #expect(member.portion < before)
        #expect(MemberWeight.record(10, for: member, mainKcal: 2400, clock: clock, in: context) == nil)

        MemberWeight.deleteAll(of: member.id, in: context)
        #expect(MemberWeight.history(of: member.id, in: context).isEmpty)
    }
}
