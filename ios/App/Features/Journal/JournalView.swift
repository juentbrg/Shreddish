import ShreddishCore
import SwiftData
import SwiftUI

/// Journal alimentaire : repas mangés / sautés, extras, réel face à la cible (US4 ; design « Écrans clairs »).
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
                    EmptyState(
                        title: "Pas de planning", systemImage: "checklist",
                        message: String(localized: "Génère ta semaine pour suivre tes repas.")
                    )
                    .paperBackground()
                }
            }
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
        // Jour choisi absent du planning affiché (nouvelle semaine) : retour au jour par défaut.
        let key = selectedKey.flatMap { selected in days.contains { $0.dayKey == selected } ? selected : nil } ?? defaultKey
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DayStrip(
                    days: days, selected: days.first { $0.dayKey == key }?.offset, today: model.clock.today,
                    idPrefix: "journal-day-"
                ) { offset in
                    selectedKey = days.first { $0.offset == offset }?.dayKey
                }
                if let day = days.first(where: { $0.dayKey == key }) {
                    JournalDayView(day: day)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .paperBackground()
    }
}

struct JournalDayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    let day: DayPlan
    @State private var showAddExtra = false

    /// Prochain repas à cocher, mis en avant le jour même.
    private var nextMeal: Meal? {
        guard day.day == model.clock.today else { return nil }
        return day.sortedMeals.first { $0.status == .planned }
    }

    var body: some View {
        let meals = day.sortedMeals
        VStack(alignment: .leading, spacing: 18) {
            JournalHeroCard(day: day, isToday: day.day == model.clock.today)
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(
                    title: "Repas du jour",
                    trailing: String(localized: "\(meals.filter { $0.status != .planned }.count) sur \(meals.count) cochés")
                )
                ForEach(meals) { meal in
                    if meal === nextMeal {
                        NextMealCard(meal: meal) { status, fraction in set(meal, status, fraction: fraction) }
                    } else {
                        MealStatusRow(meal: meal) { status, fraction in set(meal, status, fraction: fraction) }
                    }
                }
            }
            extras
        }
        .sheet(isPresented: $showAddExtra) {
            QuickAddView(day: day)
        }
    }

    private func set(_ meal: Meal, _ status: MealStatus, fraction: Double?) {
        meal.setStatus(status, at: model.clock.now)
        meal.eatenFraction = status == .eaten && fraction != 1 ? fraction : nil
        try? context.save()
    }

    private var extras: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Extras")
                    .font(Theme.text(.subheadline, .bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Ajouter", systemImage: "plus") { showAddExtra = true }
                    .buttonStyle(CompactButtonStyle())
                    .accessibilityIdentifier("addExtra")
            }
            if day.sortedExtras.isEmpty {
                Text("Tout ce qui n'était pas prévu : recherche, code-barres, favoris.")
                    .font(Theme.text(.footnote))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(day.sortedExtras) { extra in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(extra.name).font(Theme.text(.subheadline, .semibold))
                        if let quantity = extra.quantityLabel, !quantity.isEmpty {
                            Text(quantity).font(Theme.text(.caption)).foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer()
                    Text(Format.kcal(extra.kcal)).font(Theme.text(.subheadline)).foregroundStyle(Theme.muted)
                    DeleteRowButton(label: extra.name) {
                        context.delete(extra)
                        try? context.save()
                    }
                }
            }
        }
        .card()
    }
}

/// Carte du haut : mangé face à la cible, macros qui se remplissent.
struct JournalHeroCard: View {
    let day: DayPlan
    let isToday: Bool

    var body: some View {
        let actual = day.actualTotals
        let targets = day.plan?.targets
        let target = Double(targets?.targetKcal ?? 0)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(isToday ? "Mangé aujourd'hui" : "Mangé ce jour")
                    .font(Theme.text(.footnote, .medium))
                    .foregroundStyle(Theme.muted)
                Spacer()
                if target > 0 { remainingBadge(actual: actual.kcal, target: target) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.number(actual.kcal, digits: 0))
                    .font(Theme.display(38, .heavy, relativeTo: .largeTitle))
                if target > 0 {
                    Text("/ \(Format.kcal(target))")
                        .font(Theme.text(.callout))
                        .foregroundStyle(Theme.muted)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("actualKcal")
            if target > 0 {
                ProgressBar(value: actual.kcal / target, fill: actual.kcal > target * 1.1 ? Theme.tomato : Theme.ink,
                    track: Theme.line, height: 8)
            }
            HStack(spacing: 8) {
                MacroProgressTile(title: "Protéines", value: actual.proteinG, target: targets.map { Double($0.proteinG) },
                    palette: Theme.protein)
                MacroProgressTile(title: "Glucides", value: actual.carbsG, target: targets.map { Double($0.carbsG) },
                    palette: Theme.carbs)
                MacroProgressTile(title: "Lipides", value: actual.fatG, target: targets.map { Double($0.fatG) },
                    palette: Theme.fat)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func remainingBadge(actual: Double, target: Double) -> some View {
        let left = target - actual
        let over = left < 0
        return Text(over ? String(localized: "\(Format.kcal(-left)) en trop") : String(localized: "Reste \(Format.kcal(left))"))
            .font(Theme.text(.caption, .bold))
            .foregroundStyle(over ? Theme.tomatoInk : Theme.success)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(over ? Theme.tomatoSoft : Theme.successSoft, in: Capsule())
    }
}

/// Barre de progression arrondie, plafonnée à 100 %.
struct ProgressBar: View {
    let value: Double
    var fill: Color = Theme.ink
    var track: Color = Theme.line
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Tuile de macro : mangé face à la cible, avec sa jauge.
struct MacroProgressTile: View {
    let title: String
    let value: Double
    let target: Double?
    let palette: MacroPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title)).font(Theme.text(.caption, .bold)).foregroundStyle(palette.ink)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Format.number(value, digits: 0)).font(Theme.text(.headline, .bold)).foregroundStyle(Theme.ink)
                if let target {
                    Text("/ \(Format.grams(target))").font(Theme.text(.caption2)).foregroundStyle(Theme.muted)
                }
            }
            if let target, target > 0 {
                ProgressBar(value: value / target, fill: palette.bar, track: palette.ink.opacity(0.15), height: 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(palette.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Prochain repas du jour : mis en avant, trois actions directes.
struct NextMealCard: View {
    let meal: Meal
    let onSelect: (MealStatus, Double?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MealTile(type: meal.type, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\([meal.time, meal.type.label].compactMap(\.self).joined(separator: " · ")) · À venir")
                        .font(Theme.text(.caption, .bold))
                        .foregroundStyle(meal.type.tileColors.ink)
                    Text(meal.name).font(Theme.text(.headline, .bold)).foregroundStyle(Theme.ink)
                    let macros = "P \(Format.grams(meal.proteinG)) · G \(Format.grams(meal.carbsG)) · L \(Format.grams(meal.fatG))"
                    Text("\(Format.kcal(meal.kcal)) · \(macros)")
                        .font(Theme.text(.caption))
                        .foregroundStyle(Theme.muted)
                }
            }
            .accessibilityElement(children: .combine)
            Grid(horizontalSpacing: 8) {
                GridRow {
                    action("Mangé", prominent: true) { onSelect(.eaten, nil) }
                        .gridCellColumns(2)
                    action("Moitié") { onSelect(.eaten, 0.5) }
                    action("Sauté") { onSelect(.skipped, nil) }
                }
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.accent, lineWidth: 2))
    }

    private func action(_ title: LocalizedStringKey, prominent: Bool = false, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title)
                .font(Theme.text(.subheadline, .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(prominent ? Theme.onAccent : Theme.ink)
                .background(prominent ? Theme.accent : Theme.line, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(Text(title)) : \(meal.name)"))
    }
}

/// Ligne d'un repas : rond à cocher (mangé), statut, appui long pour une part ou « sauté ».
struct MealStatusRow: View {
    let meal: Meal
    let onSelect: (MealStatus, Double?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onSelect(meal.status == .planned ? .eaten : .planned, nil)
            } label: {
                statusCircle.frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(meal.status == .planned ? "Mangé : \(meal.name)" : "Remettre à prévu : \(meal.name)")
            VStack(alignment: .leading, spacing: 1) {
                Text(meal.name)
                    .font(Theme.text(.subheadline, .semibold))
                    .foregroundStyle(meal.status == .planned ? Theme.ink : Theme.muted)
                    .strikethrough(meal.status == .skipped)
                Text(subtitle).font(Theme.text(.caption)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            if let label = statusLabel {
                Text(label).font(Theme.text(.caption, .bold)).foregroundStyle(meal.status == .eaten ? Theme.success : Theme.muted)
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, 2)
        .padding(.trailing, 12)
        .background(meal.status == .planned ? Theme.card : Theme.card.opacity(0.6),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contextMenu {
            ForEach([1.0, 0.75, 0.5, 0.25], id: \.self) { fraction in
                Button(Format.fraction(fraction)) { onSelect(.eaten, fraction) }
            }
            Button("Sauté", systemImage: "xmark") { onSelect(.skipped, nil) }
            if meal.status != .planned {
                Button("Remettre à prévu", systemImage: "arrow.uturn.backward") { onSelect(.planned, nil) }
            }
        }
    }

    private var subtitle: String {
        let kcal = meal.eatenFraction.map { _ in Format.kcal(meal.eatenMacros.kcal) } ?? Format.kcal(meal.kcal)
        return ([meal.time, meal.type.label].compactMap(\.self) + [kcal]).joined(separator: " · ")
    }

    private var statusLabel: String? {
        switch meal.status {
        case .eaten: meal.eatenFraction.map { Format.fraction($0) } ?? String(localized: "Mangé")
        case .skipped: String(localized: "Sauté")
        case .planned: nil
        }
    }

    @ViewBuilder private var statusCircle: some View {
        switch meal.status {
        case .eaten:
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.success, in: Circle())
        case .skipped:
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.muted)
                .frame(width: 30, height: 30)
                .background(Theme.line, in: Circle())
        case .planned:
            Circle().strokeBorder(Theme.muted.opacity(0.45), lineWidth: 2).frame(width: 30, height: 30)
        }
    }
}
