import ShreddishCore
import SwiftData
import SwiftUI

/// Plannings actifs : semaine en cours et semaine à venir (US2, spec 006).
struct WeekView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WeeklyPlan> { $0.isCurrent }, sort: \WeeklyPlan.createdAt, order: .reverse)
    var plans: [WeeklyPlan]
    @Query var profiles: [Profile]
    @Query var allPreferences: [Preferences]
    @State private var showNewWeek = false
    @State private var confirmDelete = false
    @State private var selectedPlanID: UUID?

    private var activePlans: [WeeklyPlan] { plans.sorted { $0.startDay < $1.startDay } }

    private var shownPlan: WeeklyPlan? {
        activePlans.first { $0.id == selectedPlanID } ?? PlanStore.focusPlan(activePlans, today: model.clock.today)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let plan = shownPlan {
                    VStack(spacing: 0) {
                        if activePlans.count > 1 {
                            PlanSwitcher(plans: activePlans, selected: plan, today: model.clock.today) { selectedPlanID = $0 }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)
                        }
                        WeekPlanList(plan: plan)
                            .id(plan.id)
                    }
                    .paperBackground()
                } else {
                    emptyState.paperBackground()
                }
            }
            .navigationTitle("Ma semaine")
            .toolbar { toolbar }
            .sheet(isPresented: $showNewWeek) {
                NewWeekSheet(today: model.clock.today, activePlans: activePlans) { start in
                    showNewWeek = false
                    generate(from: start)
                }
                .presentationDetents([.medium, .large])
            }
            .confirmationDialog(
                "Supprimer ce planning ?", isPresented: $confirmDelete, titleVisibility: .visible
            ) {
                Button("Supprimer le planning", role: .destructive) {
                    if let plan = shownPlan {
                        selectedPlanID = nil
                        try? PlanStore.deletePlan(plan, in: context)
                    }
                }
            } message: {
                Text("Repas, courses et journal de ces jours supprimés. Pesées conservées.")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if !plans.isEmpty {
                    Button("Planifier une semaine", systemImage: "calendar.badge.plus") { showNewWeek = true }
                        .disabled(model.isBusy || !model.hasAPIKey)
                        .accessibilityIdentifier("newWeek")
                    Button("Supprimer ce planning", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("deletePlan")
                }
                NavigationLink {
                    PlanHistoryView()
                } label: {
                    Label("Historique", systemImage: "clock.arrow.circlepath")
                }
            } label: {
                Label("Options", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("weekMenu")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Pas encore de planning", systemImage: "fork.knife")
        } description: {
            if model.hasAPIKey {
                Text("7 jours de repas simples, calés sur tes cibles.")
            } else {
                Text("Ajoute ta clé API OpenAI pour générer tes repas.")
            }
        } actions: {
            if model.hasAPIKey {
                Button("Planifier ma semaine") { showNewWeek = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("generateWeek")
            } else {
                NavigationLink("Ajouter ma clé API") { APIKeyView() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("addAPIKey")
            }
        }
    }

    private func generate(from start: LocalDay) {
        guard let profile = profiles.first, let preferences = allPreferences.first else { return }
        let generator = model.generator
        let context = context
        selectedPlanID = nil
        Task {
            await model.run("Préparation de ta semaine…") { () async throws(AIError) -> [ValidationIssue] in
                try await generator.generateWeek(profile: profile, preferences: preferences, startDay: start, in: context)
            }
        }
    }
}

/// Bascule entre semaine en cours et semaine à venir.
struct PlanSwitcher: View {
    let plans: [WeeklyPlan]
    let selected: WeeklyPlan
    let today: LocalDay
    let select: (UUID) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(plans) { plan in
                let isSelected = plan.id == selected.id
                Button {
                    select(plan.id)
                } label: {
                    VStack(spacing: 1) {
                        Text(plan.contains(today) ? "En cours" : plan.startDay > today ? "À venir" : "Terminée")
                            .font(Theme.text(.subheadline, .bold))
                        Text("\(Format.shortDate(plan.startDay)) → \(Format.shortDate(plan.endDay))")
                            .font(Theme.text(.caption))
                    }
                    .foregroundStyle(isSelected ? Theme.paper : Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(isSelected ? Theme.ink : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// Choix du premier jour de la semaine à planifier : aujourd'hui ou jusqu'à 13 jours plus tard (spec 006).
struct NewWeekSheet: View {
    let today: LocalDay
    let activePlans: [WeeklyPlan]
    let start: (LocalDay) -> Void
    @State private var startDay: LocalDay?

    private var chosen: LocalDay { startDay ?? today }

    /// Raccourcis : aujourd'hui, demain, prochain lundi, prochain dimanche, lendemain du dernier planning.
    private var shortcuts: [(String, LocalDay)] {
        var items: [(String, LocalDay)] = [("Aujourd'hui", today), ("Demain", today.adding(days: 1))]
        for (label, weekday) in [("Lundi prochain", 2), ("Dimanche prochain", 1)] {
            let day = Format.next(weekday: weekday, after: today)
            if !items.contains(where: { $0.1 == day }) { items.append((label, day)) }
        }
        if let last = activePlans.map(\.endDay).max()?.adding(days: 1), last > today,
           last <= today.adding(days: 13), !items.contains(where: { $0.1 == last }) {
            items.append(("Après le planning actuel", last))
        }
        return items.sorted { $0.1 < $1.1 }
    }

    private var effect: String {
        if chosen <= today {
            return "Planning actuel archivé, journal conservé."
        }
        let overlapped = activePlans.filter { $0.contains(chosen) || $0.startDay > chosen }
        guard !overlapped.isEmpty else { return "Planning en cours inchangé." }
        return "Jours prévus à partir de cette date remplacés."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionTitle(title: "Premier jour")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(shortcuts, id: \.1) { label, day in
                            let isSelected = day == chosen
                            Button {
                                startDay = day
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(label).font(Theme.text(.subheadline, .semibold))
                                    Text(Format.weekdayLong(day)).font(Theme.text(.caption))
                                }
                                .foregroundStyle(isSelected ? Theme.onGreen : Theme.ink)
                                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                                .padding(.horizontal, 12)
                                .background(
                                    isSelected ? Theme.green : Theme.card,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    DatePicker(
                        "Autre date",
                        selection: Binding(
                            get: { chosen.startDate(calendar: .current) },
                            set: { startDay = LocalDay(date: $0, calendar: .current) }
                        ),
                        in: today.startDate(calendar: .current)...today.adding(days: 13).startDate(calendar: .current),
                        displayedComponents: .date
                    )
                    .font(Theme.text(.body))
                    .card()
                    Text("Du \(Format.weekdayLong(chosen)) au \(Format.weekdayLong(chosen.adding(days: 6))). \(effect)")
                        .font(Theme.text(.footnote))
                        .foregroundStyle(Theme.muted)
                }
                .padding(20)
            }
            .paperBackground()
            .navigationTitle("Planifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Générer") { start(chosen) }
                        .accessibilityIdentifier("startGeneration")
                }
            }
        }
    }
}

/// Planning de 7 jours (courant ou historique) : sélecteur de jour, carte du jour et repas (design « Marché »).
struct WeekPlanList: View {
    @Environment(AppModel.self) private var model
    @Query var allPreferences: [Preferences]
    let plan: WeeklyPlan
    @State private var selectedOffset: Int?

    private var days: [DayPlan] { plan.sortedDays }

    private var selectedDay: DayPlan? {
        let offset = selectedOffset ?? days.first { $0.day == model.clock.today }?.offset ?? 0
        return days.first { $0.offset == offset } ?? days.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if plan.isCurrent, let warning = model.warningMessage {
                    WarningBadge(text: warning).card()
                }
                DayStrip(days: days, selected: selectedDay?.offset, today: model.clock.today) { selectedOffset = $0 }
                if let day = selectedDay {
                    DayContent(day: day)
                }
                weekCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .paperBackground()
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "La semaine", trailing: Format.range(plan, calendar: model.clock.calendar))
            VStack(alignment: .leading, spacing: 10) {
                if let targets = plan.targets {
                    LabeledContent("Cible", value: Format.kcal(Double(targets.targetKcal)))
                }
                if let preferences = allPreferences.first {
                    WeekCostRow(cost: days.reduce(0) { $0 + $1.plannedCostEUR }, preferences: preferences)
                }
                if !plan.prepSessions.isEmpty {
                    NavigationLink {
                        PrepSessionView(sessions: plan.prepSessions, startDay: plan.startDay)
                    } label: {
                        Label("\(plan.prepSessions.count) session(s) de batch cooking", systemImage: "frying.pan")
                    }
                }
            }
            .font(Theme.text(.subheadline))
            .card()
        }
    }
}

/// Sélecteur des 7 jours.
struct DayStrip: View {
    let days: [DayPlan]
    let selected: Int?
    let today: LocalDay
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days) { day in
                let isSelected = day.offset == selected
                Button {
                    select(day.offset)
                } label: {
                    VStack(spacing: 2) {
                        Text(Format.weekdayShort(day.day))
                            .font(Theme.text(.caption2, .semibold))
                        Text("\(day.day.day)")
                            .font(Theme.display(19, .bold, relativeTo: .headline))
                        Circle()
                            .fill(day.day == today ? (isSelected ? Theme.onGreen : Theme.tomato) : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .foregroundStyle(isSelected ? Theme.onGreen : Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(isSelected ? Theme.green : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Format.weekdayLong(day.day) + (day.day == today ? ", aujourd'hui" : ""))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("day-\(day.offset)")
            }
        }
    }
}

/// Badge hors cible (> 10 %) d'un jour (FR-011). Le budget se contrôle à la semaine (spec 003).
struct DayBadges: View {
    let day: DayPlan
    let targets: NutritionTargets?

    var body: some View {
        let totals = day.plannedTotals
        let deviation = Totals.deviation(totals, targetKcal: Double(targets?.targetKcal ?? 0))
        let carbsTarget = targets?.macros.carbsG ?? 0
        let carbsDeviation = carbsTarget > 0 ? totals.carbsG / carbsTarget - 1 : 0
        if Totals.isOffTarget(deviation) {
            WarningBadge(text: "Hors cible \(Format.percent(deviation, signed: true))")
        }
        // Spec 004 : glucides nettement au-dessus de la cible.
        if carbsDeviation > 0.15 {
            WarningBadge(text: "Glucides \(Format.percent(carbsDeviation, signed: true))", systemImage: "leaf.fill")
        }
    }
}

/// Coût estimé de la semaine face au budget et à la tolérance (spec 003, FR-207).
struct WeekCostRow: View {
    let cost: Double
    let preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Courses estimées", value: Format.euros(cost))
                .accessibilityIdentifier("weekCost")
            let budget = Format.euros(preferences.weeklyBudget)
            ProgressView(value: min(cost, preferences.budgetCeiling), total: max(preferences.budgetCeiling, 1))
                .tint(cost > preferences.weeklyBudget + 0.005 ? Theme.tomato : Theme.green)
            Text("Budget \(budget) · tolérance \(Format.percent(preferences.tolerance)) · \(preferences.storeName)")
                .font(Theme.text(.caption))
                .foregroundStyle(Theme.muted)
            if cost > preferences.weeklyBudget + 0.005 {
                let beyond = cost > preferences.budgetCeiling + 0.005
                WarningBadge(
                    text: beyond ? "Au-dessus de la tolérance" : "Au-dessus du budget, dans la tolérance",
                    systemImage: "eurosign.circle.fill"
                )
            }
        }
    }
}
