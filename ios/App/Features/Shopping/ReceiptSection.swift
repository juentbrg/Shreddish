import ShreddishCore
import SwiftData
import SwiftUI

/// Ticket réel (spec 017, FR-1718) : montant payé en caisse, comparé au ticket estimé, partageable.
struct ReceiptSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query private var receipts: [ShoppingReceipt]
    @Query private var members: [HouseholdMember]
    @State private var amount = ""
    @State private var sharing = false
    @FocusState private var focused: Bool
    let plan: WeeklyPlan
    let budget: Double

    init(plan: WeeklyPlan, budget: Double) {
        self.plan = plan
        self.budget = budget
        let planID = plan.id
        _receipts = Query(filter: #Predicate<ShoppingReceipt> { $0.planID == planID }, sort: \.recordedAt, order: .reverse)
    }

    private var comparison: ReceiptComparison? {
        receipts.first.map {
            ReceiptComparison(estimatedEUR: plan.shoppingSummary.checkoutEur, paidEUR: $0.amountEUR, budgetEUR: budget)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ticket réel")
                .font(Theme.text(.headline, .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            if let comparison {
                LabeledContent("Payé en caisse", value: Format.euros(comparison.paidEUR))
                Text(Self.verdict(comparison))
                    .foregroundStyle(comparison.difference <= 0 ? Theme.green : Theme.tomatoInk)
            }
            TextField(comparison == nil ? "Montant payé (€)" : "Corriger le montant (€)", text: $amount, axis: .vertical)
                .keyboardType(.decimalPad)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("receiptAmount")
            Button("Enregistrer", action: save)
                .buttonStyle(PillButtonStyle())
                .disabled(parsed == nil)
                .accessibilityIdentifier("saveReceipt")
            if comparison != nil {
                Button("Partager mon ticket", systemImage: "square.and.arrow.up") { sharing = true }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .accessibilityIdentifier("shareReceipt")
            }
        }
        .font(Theme.text(.subheadline))
        .card()
        .sheet(isPresented: $sharing) {
            if let comparison {
                ShareCardSheet(title: String(localized: "Mon ticket"), card: ReceiptShareCard(
                    comparison: comparison, meals: plan.days.reduce(0) { $0 + $1.meals.count },
                    portions: Household.portions(members)
                ))
            }
        }
    }

    private var parsed: Double? {
        Format.parse(amount).flatMap { ShoppingReceipt.amountRange.contains($0) ? $0 : nil }
    }

    private func save() {
        guard let parsed else { return }
        ShoppingReceipt.record(parsed, planID: plan.id, at: model.clock.now, in: context)
        try? context.save()
        amount = ""
        focused = false
    }

    static func verdict(_ comparison: ReceiptComparison) -> String {
        let gap = Format.euros(abs(comparison.difference))
        if abs(comparison.difference) < 0.5 {
            return String(localized: "Pile l'estimation.")
        }
        return comparison.difference < 0
            ? String(localized: "\(gap) de moins que prévu.")
            : String(localized: "\(gap) de plus que prévu.")
    }
}
