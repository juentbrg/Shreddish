import ShreddishCore
import SwiftData
import SwiftUI

/// Journal alimentaire : repas mangés / sautés, extras, réel face au prévu et à la cible (US4).
struct JournalView: View {
    @Environment(AppModel.self) private var model
    @Query(filter: #Predicate<WeeklyPlan> { $0.isCurrent }, sort: \WeeklyPlan.createdAt, order: .reverse)
    var plans: [WeeklyPlan]
    @State private var selectedKey: Int?

    /// Planning du jour (spec 006 : semaine en cours avant la semaine à venir).
    private var plan: WeeklyPlan? { PlanStore.focusPlan(plans, today: model.clock.today) }

    var body: some View {
        NavigationStack {
            Group {
                if let plan {
                    content(plan)
                } else {
                    ContentUnavailableView(
                        "Pas de planning", systemImage: "checklist",
                        description: Text("Génère ta semaine pour suivre tes repas.")
                    )
                }
            }
            .themedList()
            .navigationTitle("Journal")
            .toolbar {
                if let plan {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            WeeklySummaryView(plan: plan)
                        } label: {
                            Label("Bilan de la semaine", systemImage: "chart.bar")
                        }
                        .accessibilityIdentifier("weeklySummary")
                    }
                }
            }
        }
    }

    private func content(_ plan: WeeklyPlan) -> some View {
        let days = plan.sortedDays
        let todayKey = model.clock.today.key
        let defaultKey = days.first { $0.dayKey == todayKey }?.dayKey ?? days.first?.dayKey
        let key = selectedKey ?? defaultKey
        return VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days) { day in
                        DayChip(day: day, isSelected: day.dayKey == key, isToday: day.dayKey == todayKey) {
                            selectedKey = day.dayKey
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            if let day = days.first(where: { $0.dayKey == key }) {
                JournalDayView(day: day)
            }
        }
    }
}

struct DayChip: View {
    @Environment(AppModel.self) private var model
    let day: DayPlan
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    var body: some View {
        let date = day.day.startDate(calendar: model.clock.calendar)
        Button(action: action) {
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.abbreviated).locale(Format.locale)))
                    .font(.caption)
                Text(date.formatted(.dateTime.day().locale(Format.locale)))
                    .font(.headline)
            }
            .frame(width: 48, height: 52)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Format.day(day.day, calendar: model.clock.calendar))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct JournalDayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    let day: DayPlan
    @State private var showAddExtra = false

    var body: some View {
        List {
            Section("Bilan du jour") {
                let actual = day.actualTotals
                let planned = day.plannedTotals
                if let targets = day.plan?.targets {
                    TargetGauge(title: "Calories mangées", value: actual.kcal, target: Double(targets.targetKcal), format: Format.kcal)
                    TargetGauge(title: "Protéines", value: actual.proteinG, target: Double(targets.proteinG), format: Format.grams)
                }
                LabeledContent("Prévu", value: Format.kcal(planned.kcal))
                LabeledContent("Réel", value: Format.kcal(actual.kcal))
                    .accessibilityIdentifier("actualKcal")
                MacroLine(macros: actual)
            }
            Section("Repas du planning") {
                ForEach(day.sortedMeals) { meal in
                    MealStatusRow(meal: meal) { status in
                        meal.setStatus(meal.status == status ? .planned : status, at: model.clock.now)
                        try? context.save()
                    }
                }
            }
            Section {
                ForEach(day.sortedExtras) { extra in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(extra.name)
                            if let quantity = extra.quantityLabel, !quantity.isEmpty {
                                Text(quantity).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(Format.kcal(extra.kcal)).foregroundStyle(.secondary)
                        DeleteRowButton(label: extra.name) {
                            context.delete(extra)
                            try? context.save()
                        }
                    }
                }
                .onDelete { offsets in
                    let extras = day.sortedExtras
                    for index in offsets { context.delete(extras[index]) }
                    try? context.save()
                }
                Button("Ajouter un extra", systemImage: "plus") { showAddExtra = true }
                    .accessibilityIdentifier("addExtra")
            } header: {
                Text("Extras")
            } footer: {
                Text("Tout ce qui n'était pas prévu.")
            }
        }
        .sheet(isPresented: $showAddExtra) {
            AddExtraView(day: day)
        }
    }
}

struct MealStatusRow: View {
    let meal: Meal
    let onSelect: (MealStatus) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.type.label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(meal.name)
                    .strikethrough(meal.status == .skipped)
                Text(Format.kcal(meal.kcal))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusButton(.eaten, symbol: "checkmark.circle.fill", label: "Mangé", tint: .green)
            statusButton(.skipped, symbol: "xmark.circle.fill", label: "Sauté", tint: .gray)
        }
    }

    private func statusButton(_ status: MealStatus, symbol: String, label: String, tint: Color) -> some View {
        Button {
            onSelect(status)
        } label: {
            Image(systemName: meal.status == status ? symbol : symbol.replacingOccurrences(of: ".fill", with: ""))
                .font(.title2)
                .foregroundStyle(meal.status == status ? tint : .secondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) : \(meal.name)")
        .accessibilityAddTraits(meal.status == status ? .isSelected : [])
    }
}
