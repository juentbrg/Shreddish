import ShreddishCore
import SwiftData
import SwiftUI

/// Réglage manuel des protéines, lipides et de l'ajustement calorique (FR-003).
struct MacroSettingsView: View {
    @Environment(AppModel.self) private var model
    @Query var profiles: [Profile]

    var body: some View {
        Form {
            if let profile = profiles.first {
                overrideSection(
                    title: "Protéines", unit: "g/kg",
                    value: Binding(get: { profile.proteinPerKg }, set: { profile.proteinPerKg = $0 }),
                    defaultValue: profile.goal.defaultProteinPerKg,
                    range: NutritionCalculator.proteinPerKgRange, step: 0.1,
                    format: { "\(Format.number($0)) g/kg" }
                )
                overrideSection(
                    title: "Lipides", unit: "g/kg",
                    value: Binding(get: { profile.fatPerKg }, set: { profile.fatPerKg = $0 }),
                    defaultValue: NutritionCalculator.defaultFatPerKg,
                    range: NutritionCalculator.fatPerKgRange, step: 0.1,
                    format: { "\(Format.number($0)) g/kg" }
                )
                overrideSection(
                    title: "Ajustement calorique", unit: "%",
                    value: Binding(get: { profile.calorieAdjustment }, set: { profile.calorieAdjustment = $0 }),
                    defaultValue: profile.goal.defaultCalorieAdjustment,
                    range: NutritionCalculator.calorieAdjustmentRange, step: 0.01,
                    format: { Format.percent($0, signed: true) }
                )
                if let targets = profile.targets(clock: model.clock) {
                    Section("Résultat") {
                        LabeledContent("Cible", value: Format.kcal(Double(targets.targetKcal)))
                        MacroLine(macros: targets.macros)
                    }
                }
            }
        }
        .themedList()
        .navigationTitle("Macros")
    }

    private func overrideSection(
        title: String, unit: String, value: Binding<Double?>, defaultValue: Double,
        range: ClosedRange<Double>, step: Double, format: @escaping (Double) -> String
    ) -> some View {
        Section(title) {
            Toggle("Personnaliser", isOn: Binding(
                get: { value.wrappedValue != nil },
                set: { value.wrappedValue = $0 ? defaultValue : nil }
            ))
            if let current = value.wrappedValue {
                Stepper(
                    format(current),
                    value: Binding(get: { current }, set: { value.wrappedValue = ($0 / step).rounded() * step }),
                    in: range, step: step
                )
            } else {
                LabeledContent("Par défaut", value: format(defaultValue))
            }
        }
    }
}
