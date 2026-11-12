import ShreddishCore
import SwiftData
import SwiftUI

/// Détail d'un repas : ingrédients, étapes, temps, coût, macros (FR-010).
struct MealDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query var profiles: [Profile]
    @Query var allPreferences: [Preferences]
    let meal: Meal

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(meal.type.label.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(meal.name)
                        .font(.title2.bold())
                    HStack(spacing: 14) {
                        Label("\(meal.prepMinutes) min", systemImage: "timer")
                        Label(Format.euros(meal.costEUR), systemImage: "basket")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                if let ref = meal.prepSessionRef,
                   let session = meal.day?.plan?.prepSessions.first(where: { $0.index == ref }) {
                    Label("Préparé pendant « \(session.title) »", systemImage: "frying.pan")
                        .font(.subheadline)
                }
            }
            Section("Valeurs") {
                LabeledContent("Calories", value: Format.kcal(meal.kcal))
                LabeledContent("Protéines", value: Format.grams(meal.proteinG))
                LabeledContent("Glucides", value: Format.grams(meal.carbsG))
                LabeledContent("Lipides", value: Format.grams(meal.fatG))
            }
            Section("Ingrédients") {
                ForEach(Array(meal.ingredients.enumerated()), id: \.offset) { _, ingredient in
                    HStack {
                        Text(ingredient.name)
                        Spacer()
                        Text(Format.quantity(ingredient.quantity, unit: ingredient.measureUnit ?? .g))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            Section("Préparation") {
                ForEach(Array(meal.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1).")
                            .bold()
                            .monospacedDigit()
                        Text(step)
                    }
                }
            }
            if meal.day?.plan?.isCurrent == true {
                Section {
                    Button("Remplacer ce repas", systemImage: "arrow.triangle.2.circlepath") {
                        MealReplacement.run(
                            meal: meal, profile: profiles.first, preferences: allPreferences.first, model: model, context: context
                        )
                        dismiss()
                    }
                    .disabled(model.isBusy)
                } footer: {
                    Text("Nouvelle proposition aux calories proches, les autres repas ne changent pas.")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
