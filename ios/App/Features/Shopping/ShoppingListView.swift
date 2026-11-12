import ShreddishCore
import SwiftData
import SwiftUI

/// Liste de courses agrégée par rayon depuis le planning courant (US5, FR-015).
struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WeeklyPlan> { $0.isCurrent }, sort: \WeeklyPlan.createdAt, order: .reverse)
    var plans: [WeeklyPlan]
    @Query var allPreferences: [Preferences]

    var body: some View {
        NavigationStack {
            Group {
                if let plan = plans.first, !plan.shoppingItems.isEmpty {
                    list(plan)
                } else {
                    ContentUnavailableView(
                        "Liste vide", systemImage: "cart",
                        description: Text("La liste se remplit à partir de ton planning de la semaine.")
                    )
                }
            }
            .navigationTitle("Courses")
        }
    }

    private func list(_ plan: WeeklyPlan) -> some View {
        let items = plan.shoppingItems
        let grouped = Dictionary(grouping: items, by: \.aisle)
        let aisles = grouped.keys.sorted { $0.sortIndex < $1.sortIndex }
        let checked = items.filter(\.isChecked).count
        return List {
            Section {
                if let preferences = allPreferences.first {
                    WeekCostRow(cost: items.reduce(0) { $0 + $1.costEUR }, preferences: preferences)
                } else {
                    LabeledContent("Coût estimé", value: Format.euros(items.reduce(0) { $0 + $1.costEUR }))
                }
                ProgressView(value: Double(checked), total: Double(max(items.count, 1))) {
                    Text("\(checked) / \(items.count) dans le panier")
                        .font(.subheadline)
                }
            }
            ForEach(aisles, id: \.self) { aisle in
                Section(aisle.label) {
                    ForEach((grouped[aisle] ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { item in
                        ShoppingRow(item: item) {
                            item.isChecked.toggle()
                            try? context.save()
                        }
                    }
                }
            }
            if checked > 0 {
                Section {
                    Button("Tout décocher") {
                        for item in items { item.isChecked = false }
                        try? context.save()
                    }
                }
            }
        }
    }
}

struct ShoppingRow: View {
    let item: ShoppingItem
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? Color.accentColor : .secondary)
                VStack(alignment: .leading) {
                    Text(item.name)
                        .strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                    Text(Format.euros(item.costEUR))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Format.quantity(item.totalQuantity, unit: item.unit))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(item.isChecked ? .isSelected : [])
        .accessibilityIdentifier("shopping-\(item.key)")
    }
}
