import ShreddishCore
import SwiftData
import SwiftUI

/// Ajout d'un extra libre (FR-018). Kcal vides : calculées depuis les macros.
struct AddExtraView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let day: DayPlan

    @State private var name = ""
    @State private var quantity = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    private var macros: MacroTotals {
        let protein = Format.parse(protein) ?? 0
        let carbs = Format.parse(carbs) ?? 0
        let fat = Format.parse(fat) ?? 0
        let fromMacros = 4 * protein + 4 * carbs + 9 * fat
        return MacroTotals(kcal: Format.parse(kcal) ?? fromMacros, proteinG: protein, carbsG: carbs, fatG: fat)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && macros.kcal > 0
            && [kcal, protein, carbs, fat].allSatisfy { $0.isEmpty || (Format.parse($0) ?? -1) >= 0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom (ex. carré de chocolat)", text: $name)
                        .accessibilityIdentifier("extraName")
                    TextField("Quantité (optionnel)", text: $quantity)
                }
                Section {
                    numberField("Calories (kcal)", text: $kcal, id: "extraKcal")
                    numberField("Protéines (g)", text: $protein, id: "extraProtein")
                    numberField("Glucides (g)", text: $carbs, id: "extraCarbs")
                    numberField("Lipides (g)", text: $fat, id: "extraFat")
                } footer: {
                    if kcal.isEmpty, macros.kcal > 0 {
                        Text("Calculé depuis les macros : \(Format.kcal(macros.kcal)).")
                    }
                }
            }
            .navigationTitle("Extra")
            .keyboardDoneButton()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { save() }
                        .disabled(!isValid)
                        .accessibilityIdentifier("saveExtra")
                }
            }
        }
    }

    private func numberField(_ title: String, text: Binding<String>, id: String) -> some View {
        LabeledContent(title) {
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(id)
        }
    }

    private func save() {
        let extra = ExtraEntry(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            quantityLabel: quantity.isEmpty ? nil : quantity, macros: macros, loggedAt: model.clock.now
        )
        day.extras.append(extra)
        try? context.save()
        dismiss()
    }
}
