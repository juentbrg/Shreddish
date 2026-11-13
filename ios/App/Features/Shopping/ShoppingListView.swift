import ShreddishCore
import SwiftData
import SwiftUI

/// Liste de courses agrégée par rayon depuis le planning courant (US5, FR-015 ; design « Marché »).
struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WeeklyPlan> { $0.isCurrent }, sort: \WeeklyPlan.createdAt, order: .reverse)
    var plans: [WeeklyPlan]
    @Query var allPreferences: [Preferences]
    @State private var aisleFilter: Aisle?
    @State private var selectedPlanID: UUID?
    @Environment(AppModel.self) private var model

    private var activePlans: [WeeklyPlan] { plans.sorted { $0.startDay < $1.startDay } }

    /// Par défaut la semaine la plus lointaine : on fait les courses pour la semaine à venir (spec 006).
    private var shownPlan: WeeklyPlan? { activePlans.first { $0.id == selectedPlanID } ?? activePlans.last }

    var body: some View {
        NavigationStack {
            Group {
                if let plan = shownPlan, !plan.shoppingItems.isEmpty {
                    list(plan)
                } else {
                    ContentUnavailableView(
                        "Liste vide", systemImage: "cart",
                        description: Text("La liste se remplit à partir de ton planning de la semaine.")
                    )
                    .paperBackground()
                }
            }
            .navigationTitle("Ma liste")
        }
    }

    private func list(_ plan: WeeklyPlan) -> some View {
        let items = plan.shoppingItems
        let grouped = Dictionary(grouping: items, by: \.aisle)
        let aisles = grouped.keys.sorted { $0.sortIndex < $1.sortIndex }
        let visible = aisleFilter.map { [$0] } ?? aisles
        let checked = items.filter(\.isChecked).count
        let cost = items.reduce(0) { $0 + $1.costEUR }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if activePlans.count > 1 {
                    PlanSwitcher(plans: activePlans, selected: plan, today: model.clock.today) { selectedPlanID = $0 }
                }
                Text("Prix moyens en France")
                    .font(Theme.text(.subheadline))
                    .foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 12) {
                    if let preferences = allPreferences.first {
                        WeekCostRow(cost: cost, preferences: preferences)
                    } else {
                        LabeledContent("Courses estimées", value: Format.euros(cost))
                    }
                    Divider().overlay(Theme.line)
                    LabeledContent("Dans le panier", value: "\(checked) / \(items.count)")
                }
                .font(Theme.text(.subheadline))
                .card()
                AisleFilter(aisles: aisles, selected: $aisleFilter)
                ForEach(visible, id: \.self) { aisle in
                    AisleCard(aisle: aisle, items: grouped[aisle] ?? []) { item in
                        item.isChecked.toggle()
                        try? context.save()
                    }
                }
                if checked > 0 {
                    Button("Tout décocher") {
                        for item in items { item.isChecked = false }
                        try? context.save()
                    }
                    .buttonStyle(PillButtonStyle(prominent: false))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .paperBackground()
    }
}

/// Filtre par rayon.
private struct AisleFilter: View {
    let aisles: [Aisle]
    @Binding var selected: Aisle?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Tout", isSelected: selected == nil, color: Theme.card) { selected = nil }
                ForEach(aisles, id: \.self) { aisle in
                    chip(aisle.label, isSelected: selected == aisle, color: aisle.dotColor.opacity(0.22)) { selected = aisle }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.text(.subheadline, isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.paper : Theme.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(isSelected ? Theme.ink : color, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Carte d'un rayon avec ses articles.
private struct AisleCard: View {
    let aisle: Aisle
    let items: [ShoppingItem]
    let toggle: (ShoppingItem) -> Void

    var body: some View {
        let sorted = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(aisle.dotColor).frame(width: 10, height: 10)
                Text(aisle.label)
                    .font(Theme.text(.subheadline, .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.vertical, 8)
            ForEach(sorted) { item in
                ShoppingRow(item: item) { toggle(item) }
                if item.persistentModelID != sorted.last?.persistentModelID {
                    Divider().overlay(Theme.line)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct ShoppingRow: View {
    let item: ShoppingItem
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? Theme.green : Theme.muted)
                Text(item.name)
                    .font(Theme.text(.body))
                    .strikethrough(item.isChecked)
                    .foregroundStyle(item.isChecked ? Theme.muted : Theme.ink)
                Spacer()
                Text("\(Format.quantity(item.totalQuantity, unit: item.unit)) · \(Format.euros(item.costEUR))")
                    .font(Theme.text(.footnote))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(item.isChecked ? .isSelected : [])
        .accessibilityIdentifier("shopping-\(item.key)")
    }
}
