import ShreddishCore
import SwiftData
import SwiftUI

/// Régénérer un jour, avec des ingrédients à écouler (restes d'un repas sauté, d'un cheat day…).
struct RegenerateDaySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let day: DayPlan
    let today: LocalDay
    let start: ([IngredientDTO]) -> Void
    @State private var hasPantry = false
    @State private var rows: [PantryRow] = []

    /// Repas non mangés des 3 derniers jours, planning de ce jour et précédent.
    private var suggestions: [IngredientDTO] {
        guard let plan = day.plan else { return [] }
        let plans = [PlanStore.previousPlan(before: plan, in: context), plan].compactMap(\.self)
        return PlanStore.uneatenIngredients(in: plans, before: today)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Seule cette journée change.")
                        .font(Theme.text(.footnote))
                        .foregroundStyle(Theme.muted)
                    PantryQuestion(
                        hasPantry: $hasPantry, rows: $rows, suggestions: suggestions,
                        suggestionsTitle: "Pas mangés ces derniers jours"
                    )
                }
                .padding(20)
            }
            .paperBackground()
            .navigationTitle("Régénérer la journée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Régénérer") { start(hasPantry ? rows.compactMap(\.ingredient) : []) }
                        .accessibilityIdentifier("confirmRegenerateDay")
                }
            }
        }
    }
}
