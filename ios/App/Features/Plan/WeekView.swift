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

    var body: some View {
        NavigationStack {
            Group {
                if let plan = plans.first {
                    WeekPlanList(plan: plan)
                } else {
                    emptyState
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
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if !plans.isEmpty {
                    Button("Nouvelle semaine", systemImage: "arrow.clockwise") { confirmNewWeek = true }
                        .disabled(model.isBusy)
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

/// Liste des 7 jours d'un planning (courant ou historique).
struct WeekPlanList: View {
    @Environment(AppModel.self) private var model
    @Query var allPreferences: [Preferences]
    let plan: WeeklyPlan

    var body: some View {
        List {
            if plan.isCurrent, let warning = model.warningMessage {
                Section {
                    WarningBadge(text: warning)
                }
            }
            Section {
                Text(Format.range(plan, calendar: model.clock.calendar))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let targets = plan.targets {
                    LabeledContent("Cible", value: Format.kcal(Double(targets.targetKcal)))
                }
                if !plan.prepSessions.isEmpty {
                    NavigationLink {
                        PrepSessionView(sessions: plan.prepSessions, startDay: plan.startDay)
                    } label: {
                        Label("\(plan.prepSessions.count) session(s) de batch cooking", systemImage: "frying.pan")
                    }
                }
            }
            ForEach(plan.sortedDays) { day in
                Section {
                    NavigationLink {
                        DayView(day: day)
                    } label: {
                        DaySummaryRow(day: day, targets: plan.targets, budget: allPreferences.first?.dailyBudgetEUR)
                    }
                    .accessibilityIdentifier("day-\(day.offset)")
                }
            }
        }
    }
}

struct DaySummaryRow: View {
    @Environment(AppModel.self) private var model
    let day: DayPlan
    let targets: NutritionTargets?
    let budget: Double?

    var body: some View {
        let totals = day.plannedTotals
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Format.day(day.day, calendar: model.clock.calendar))
                    .font(.headline)
                if day.day == model.clock.today {
                    Text("Aujourd'hui")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
            }
            ForEach(day.sortedMeals) { meal in
                Text("\(meal.type.label) · \(meal.name)")
                    .font(.subheadline)
                    .lineLimit(1)
            }
            MacroLine(macros: totals)
            DayBadges(day: day, targets: targets, budget: budget)
        }
        .padding(.vertical, 4)
    }
}

/// Badges hors cible (> 10 %) et hors budget (> 110 %) d'un jour (FR-009, FR-011).
struct DayBadges: View {
    let day: DayPlan
    let targets: NutritionTargets?
    let budget: Double?

    var body: some View {
        let deviation = Totals.deviation(day.plannedTotals, targetKcal: Double(targets?.targetKcal ?? 0))
        let overBudget = budget.map { day.plannedCostEUR > $0 * 1.1 + 0.0001 } ?? false
        if Totals.isOffTarget(deviation) || overBudget {
            HStack(spacing: 12) {
                if Totals.isOffTarget(deviation) {
                    WarningBadge(text: "Hors cible \(Format.percent(deviation, signed: true))")
                }
                if overBudget {
                    WarningBadge(text: "Budget \(Format.euros(day.plannedCostEUR))", systemImage: "eurosign.circle.fill")
                }
            }
        }
    }
}
