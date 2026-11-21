import Foundation
import SwiftData

/// Montant réellement payé pour les courses d'un planning (spec 017, FR-1718), à comparer au ticket estimé.
/// Prêt pour CloudKit : valeurs par défaut partout, aucun attribut unique.
@Model
public final class ShoppingReceipt {
    public var id = UUID()
    /// `WeeklyPlan.id` du planning concerné.
    public var planID = UUID()
    public var amountEUR = 0.0
    public var recordedAt = Date()

    public init(planID: UUID, amountEUR: Double, recordedAt: Date) {
        self.planID = planID
        self.amountEUR = amountEUR
        self.recordedAt = recordedAt
    }

    public static let amountRange = 1.0...2000.0

    /// Ticket d'un planning, s'il a été saisi.
    public static func find(planID: UUID, in context: ModelContext) -> ShoppingReceipt? {
        let descriptor = FetchDescriptor<ShoppingReceipt>(predicate: #Predicate { $0.planID == planID })
        return (try? context.fetch(descriptor))?.max { $0.recordedAt < $1.recordedAt }
    }

    /// Enregistre ou remplace le montant payé pour ce planning.
    @discardableResult
    public static func record(_ amount: Double, planID: UUID, at date: Date, in context: ModelContext) -> ShoppingReceipt? {
        guard amountRange.contains(amount) else { return nil }
        if let existing = find(planID: planID, in: context) {
            existing.amountEUR = amount
            existing.recordedAt = date
            return existing
        }
        let receipt = ShoppingReceipt(planID: planID, amountEUR: amount, recordedAt: date)
        context.insert(receipt)
        return receipt
    }
}

/// Ticket estimé contre ticket réel.
public struct ReceiptComparison: Equatable, Sendable {
    public var estimatedEUR: Double
    public var paidEUR: Double
    public var budgetEUR: Double

    public init(estimatedEUR: Double, paidEUR: Double, budgetEUR: Double) {
        self.estimatedEUR = estimatedEUR
        self.paidEUR = paidEUR
        self.budgetEUR = budgetEUR
    }

    /// Écart payé − estimé (négatif : moins cher que prévu).
    public var difference: Double { paidEUR - estimatedEUR }
    /// Écart relatif à l'estimation, nil sans estimation.
    public var relativeDifference: Double? { estimatedEUR > 0 ? difference / estimatedEUR : nil }
    public var withinBudget: Bool { budgetEUR <= 0 || paidEUR <= budgetEUR }
}
