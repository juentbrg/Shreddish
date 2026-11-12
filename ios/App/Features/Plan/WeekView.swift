import ShreddishCore
import SwiftData
import SwiftUI

/// Planning courant de 7 jours (US2).
struct WeekView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WeeklyPlan> { $0.isCurrent }, sort: \WeeklyPlan.createdAt, order: .reverse)
    var plans: [WeeklyPlan]
    @Query var profiles: [Profile]
    @Query var allPreferences: [Preferences]
    @State private var confirmNewWeek = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if let plan = plans.first {
                    WeekPlanList(plan: plan)
                } else {
                    emptyState.paperBackground()
                }
            }
            .navigationTitle("Ma semaine")
            .toolbar { toolbar }
            .confirmationDialog(
                "Générer une nouvelle semaine ?", isPresented: $confirmNewWeek, titleVisibility: .visible
            ) {
                Button("Nouvelle semaine à partir d'aujourd'hui") { generate() }
            } message: {
                Text("Le planning actuel reste consultable dans l'historique.")
            }
            .confirmationDialog(
                "Supprimer ce planning ?", isPresented: $confirmDelete, titleVisibility: .visible
            ) {
                Button("Supprimer le planning", role: .destructive) {
                    if let plan = plans.first { try? PlanStore.deletePlan(plan, in: context) }
                }
            } message: {
                Text("Repas, liste de courses et extras du journal de ces 7 jours seront supprimés. Tes pesées sont conservées.")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if !plans.isEmpty {
                    Button("Nouvelle semaine", systemImage: "arrow.clockwise") { confirmNewWeek = true }
                        .disabled(model.isBusy)
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
                Text("Génère 7 jours de repas simples, pas chers et rapides, calés sur tes cibles.")
            } else {
                Text("Ajoute ta clé API OpenAI pour générer tes repas. Tes cibles restent consultables dans l'onglet Cibles.")
            }
        } actions: {
            if model.hasAPIKey {
                Button("Générer ma semaine") { generate() }
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

    private func generate() {
        guard let profile = profiles.first, let preferences = allPreferences.first else { return }
        let generator = model.generator
        let context = context
        Task {
            await model.run("Préparation de ta semaine…") { () async throws(AIError) -> [ValidationIssue] in
                try await generator.generateWeek(profile: profile, preferences: preferences, in: context)
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
