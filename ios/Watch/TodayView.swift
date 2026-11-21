import SwiftUI

/// Écran principal : kcal et protéines restantes, repas du jour, pesée.
struct TodayView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                if let day = store.day, store.isToday {
                    Section {
                        summary(day)
                    }
                    Section("Repas") {
                        if day.meals.isEmpty {
                            Text("Pas de planning aujourd'hui.").foregroundStyle(.secondary)
                        }
                        ForEach(day.meals) { meal in
                            MealRow(meal: meal)
                        }
                    }
                    Section {
                        NavigationLink {
                            WeightEntryView(start: day.lastWeightKg ?? 75)
                        } label: {
                            Label(day.weighedToday ? "Pesée faite" : "Pesée du jour", systemImage: "scalemass")
                        }
                    }
                } else {
                    Text("Ouvre Shreddish sur ton iPhone pour envoyer ta journée.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Shreddish")
        }
    }

    private func summary(_ day: WatchDay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(max(0, day.targetKcal - day.eatenKcal)) kcal")
                .font(.title2.bold())
                .foregroundStyle(.green)
            Text("restantes · \(max(0, day.targetProteinG - day.eatenProteinG)) g de protéines")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Repas : heure, nom, boutons mangé / sauté.
private struct MealRow: View {
    @Environment(WatchStore.self) private var store
    let meal: WatchDay.Meal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text([meal.time, meal.typeLabel].compactMap(\.self).joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(meal.name)
                .font(.headline)
                .strikethrough(meal.status == "skipped")
            HStack {
                button("eaten", symbol: "checkmark.circle", label: "Mangé", tint: .green)
                button("skipped", symbol: "xmark.circle", label: "Sauté", tint: .gray)
            }
        }
        .padding(.vertical, 2)
    }

    private func button(_ status: String, symbol: String, label: LocalizedStringKey, tint: Color) -> some View {
        let selected = meal.status == status
        return Button {
            store.setStatus(meal, status)
        } label: {
            Label(label, systemImage: selected ? symbol + ".fill" : symbol)
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(selected ? tint : .secondary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Pesée à la Digital Crown, au dixième de kilo.
private struct WeightEntryView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kg: Double

    init(start: Double) {
        _kg = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(kg.formatted(.number.precision(.fractionLength(1))) + " kg")
                .font(.title.bold())
                .focusable()
                .digitalCrownRotation($kg, from: 35, through: 250, by: 0.1, sensitivity: .low)
            Button("Enregistrer") {
                store.logWeight((kg * 10).rounded() / 10)
                dismiss()
            }
            .tint(Color(red: 0.94, green: 0.54, blue: 0.39))
        }
        .navigationTitle("Pesée")
    }
}
