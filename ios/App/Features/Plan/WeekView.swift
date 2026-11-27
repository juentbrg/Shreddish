import ShreddishCore
import SwiftData
import SwiftUI

/// Plannings actifs : semaine en cours et semaine à venir (US2, spec 006).
struct WeekView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WeeklyPlan> { $0.isCurrent }, sort: \WeeklyPlan.createdAt, order: .reverse)
    var plans: [WeeklyPlan]
    @Query(filter: #Predicate<WeeklyPlan> { !$0.isCurrent }, sort: \WeeklyPlan.createdAt, order: .reverse)
    var pastPlans: [WeeklyPlan]
    @Query var profiles: [Profile]
    @Query var allPreferences: [Preferences]
    @State private var showNewWeek = false
    @State private var confirmDelete = false
    @State private var selectedPlanID: UUID?
    @State private var path = NavigationPath()
    @State private var sharing = false

    private var activePlans: [WeeklyPlan] { plans.sorted { $0.startDay < $1.startDay } }

    /// Semaines parcourables : historique (sans chevauchement, avant les plannings actifs) puis plannings actifs.
    private var weeks: [WeeklyPlan] {
        PlanStore.browsableWeeks(active: activePlans, history: pastPlans)
    }

    private var shownPlan: WeeklyPlan? {
        weeks.first { $0.id == selectedPlanID } ?? PlanStore.focusPlan(activePlans, today: model.clock.today)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let plan = shownPlan {
                    VStack(spacing: 0) {
                        WeekNavigator(
                            weeks: weeks, selected: plan, today: model.clock.today,
                            planNext: canPlanAfter(plan) ? { showNewWeek = true } : nil
                        ) { id in
                            withAnimation(.snappy) { selectedPlanID = id }
                        }
                        .frame(maxWidth: Theme.readableWidth)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        WeekPlanList(plan: plan, planNext: canPlanAfter(plan) ? { showNewWeek = true } : nil)
                            .id(plan.id)
                            .transition(.opacity)
                            .simultaneousGesture(weekSwipe(from: plan))
                    }
                    .paperBackground()
                } else {
                    emptyState.paperBackground()
                }
            }
            .navigationTitle("Ma semaine")
            .toolbar { toolbar }
            .navigationDestination(for: MealRef.self) { ref in
                if let meal = meal(ref) { MealDetailView(meal: meal) }
            }
            .navigationDestination(for: PrepRoute.self) { route in
                if let plan = activePlans.first(where: { $0.startDayKey == route.planStartKey }) {
                    PrepSessionView(sessions: plan.prepSessions, startDay: plan.startDay)
                }
            }
            .sheet(isPresented: $sharing) {
                if let plan = shownPlan {
                    ShareCardSheet(
                        title: "Ma semaine",
                        card: WeekShareCard(
                            plan: plan, cost: PlanStore.fullShoppingSummary(for: plan, in: context).weekCostEur,
                            budget: allPreferences.first?.budget(days: plan.days.count) ?? 0
                        )
                    )
                }
            }
            .onAppear(perform: openDeepLink)
            .onChange(of: model.deepLink) { openDeepLink() }
            .sheet(isPresented: $showNewWeek) {
                NewWeekSheet(today: model.clock.today, activePlans: activePlans) { start, dayCount, pantry, recipes in
                    showNewWeek = false
                    generate(from: start, dayCount: dayCount, pantry: pantry, recipes: recipes)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func meal(_ ref: MealRef) -> Meal? {
        activePlans.flatMap(\.days).first { $0.dayKey == ref.dayKey }?.meals.first { $0.order == ref.order }
    }

    /// Rappel touché : recette du repas, sessions de batch cooking ou planification de la semaine suivante.
    private func openDeepLink() {
        switch model.deepLink {
        case .meal(let ref):
            model.deepLink = nil
            guard let meal = meal(ref) else { return }
            selectedPlanID = meal.day?.plan?.id
            path = NavigationPath([ref])
        case .prep(let startKey):
            model.deepLink = nil
            guard let plan = activePlans.first(where: { $0.startDayKey == startKey }) else { return }
            selectedPlanID = plan.id
            path = NavigationPath([PrepRoute(planStartKey: startKey)])
        case .planNext:
            model.deepLink = nil
            path = NavigationPath()
            selectedPlanID = activePlans.max { $0.endDay < $1.endDay }?.id
            showNewWeek = true
        case .weighIn, .shopping, nil:
            break
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
                    Button("Partager ma semaine", systemImage: "square.and.arrow.up") { sharing = true }
                        .accessibilityIdentifier("shareWeek")
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
            .confirmationDialog(
                "Supprimer ce planning ?", isPresented: $confirmDelete, titleVisibility: .visible
            ) {
                Button("Supprimer le planning", role: .destructive) {
                    if let plan = shownPlan {
                        selectedPlanID = nil
                        try? PlanStore.deletePlan(plan, in: context)
                        model.undoableReplacement = nil
                        Task { await model.notifications.reschedule() }
                    }
                }
            } message: {
                Text("Repas, courses et journal de ces jours supprimés. Pesées conservées.")
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
                Text("Clé API absente du build : renseigne OPENAI_API_KEY dans Config/Secrets.xcconfig.")
                    .accessibilityIdentifier("missingAPIKey")
            }
        } actions: {
            if model.hasAPIKey {
                Button("Planifier ma semaine") { showNewWeek = true }
                    .buttonStyle(PillButtonStyle())
                    .frame(maxWidth: 280)
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("generateWeek")
            }
        }
    }

    /// Balayage horizontal : semaine précédente (vers la droite) ou suivante (vers la gauche).
    private func weekSwipe(from plan: WeeklyPlan) -> some Gesture {
        DragGesture(minimumDistance: 40).onEnded { value in
            let dx = value.translation.width
            guard abs(dx) > 80, abs(dx) > abs(value.translation.height) * 2,
                  let index = weeks.firstIndex(where: { $0.id == plan.id }) else { return }
            let target = dx < 0 ? index + 1 : index - 1
            guard weeks.indices.contains(target) else { return }
            withAnimation(.snappy) { selectedPlanID = weeks[target].id }
        }
    }

    /// Bouton « Planifier la suite » : seulement sous le dernier planning actif, s'il n'est pas terminé.
    private func canPlanAfter(_ plan: WeeklyPlan) -> Bool {
        model.hasAPIKey && !model.isBusy && plan.id == activePlans.last?.id && plan.endDay >= model.clock.today
    }

    private func generate(from start: LocalDay, dayCount: Int, pantry: [IngredientDTO], recipes: [SavedRecipe]) {
        guard let profile = profiles.first, let preferences = allPreferences.first else { return }
        let generator = model.generator
        let context = context
        let live = model.liveMealsHandler
        selectedPlanID = nil
        Task {
            let message = String(localized: "Préparation de ta semaine…")
            await model.run(message, recipesIn: context) { () async throws(AIError) -> [ValidationIssue] in
                let warnings = try await generator.generateWeek(
                    profile: profile, preferences: preferences, startDay: start, dayCount: dayCount, pantry: pantry,
                    recipes: recipes.map(\.dto), in: context, onText: live
                )
                // Recettes replacées : plus en attente.
                for recipe in recipes { recipe.isQueued = false }
                try? context.save()
                return warnings
            }
        }
    }
}

/// Bascule entre semaine en cours et semaine à venir.
struct WeekNavigator: View {
    let weeks: [WeeklyPlan]
    let selected: WeeklyPlan
    let today: LocalDay
    /// Planifier la semaine suivante, proposé au bout de la dernière semaine.
    var planNext: (() -> Void)?
    let select: (UUID) -> Void

    private var index: Int { weeks.firstIndex { $0.id == selected.id } ?? 0 }

    private var status: String {
        selected.contains(today)
            ? String(localized: "Semaine en cours")
            : selected.startDay > today ? String(localized: "Semaine à venir") : String(localized: "Semaine passée")
    }

    var body: some View {
        HStack(spacing: 8) {
            arrow("chevron.left", label: "Semaine précédente", id: "previousWeek", target: index - 1)
            VStack(spacing: 1) {
                Text(status)
                    .font(Theme.text(.caption, .bold))
                    .foregroundStyle(selected.contains(today) ? Theme.accent : Theme.muted)
                    .accessibilityIdentifier("weekStatus")
                Text("\(Format.shortDate(selected.startDay)) → \(Format.shortDate(selected.endDay))")
                    .font(Theme.text(.subheadline, .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity)
            if index == weeks.count - 1, let planNext {
                Button(action: planNext) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Theme.onAccent)
                        .background(Theme.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Planifier la semaine suivante")
                .accessibilityIdentifier("navPlanNext")
            } else {
                arrow("chevron.right", label: "Semaine suivante", id: "nextWeek", target: index + 1)
            }
        }
        .padding(6)
        .background(Theme.card, in: Capsule())
    }

    private func arrow(_ symbol: String, label: LocalizedStringKey, id: String, target: Int) -> some View {
        let enabled = weeks.indices.contains(target)
        return Button {
            if enabled { select(weeks[target].id) }
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(enabled ? Theme.ink : Theme.muted.opacity(0.4))
                .background(Theme.paper, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// Planning de 7 jours (courant ou historique) : sélecteur de jour, carte du jour et repas (design « Marché »).
struct WeekPlanList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query var allPreferences: [Preferences]
    let plan: WeeklyPlan
    /// Planifier la semaine qui suit ce planning ; `nil` hors dernier planning actif.
    var planNext: (() -> Void)?
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
                if plan.isCurrent {
                    // Ajustement auto des cibles (spec 002, US2) : vu à l'ouverture, pas seulement dans Profil.
                    if let message = model.calibrationMessage {
                        HStack(alignment: .top) {
                            Label(message, systemImage: "scalemass.fill")
                                .font(Theme.text(.subheadline))
                                .foregroundStyle(Theme.success)
                            Spacer(minLength: 8)
                            Button("Fermer", systemImage: "xmark") { model.calibrationMessage = nil }
                                .labelStyle(.iconOnly)
                                .foregroundStyle(Theme.muted)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .card()
                    }
                    BannedMealsBanner()
                }
                DayStrip(days: days, selected: selectedDay?.offset, today: model.clock.today) { selectedOffset = $0 }
                if let day = selectedDay {
                    DayContent(day: day)
                }
                weekCard
                if let planNext {
                    Button(action: planNext) {
                        VStack(spacing: 1) {
                            Label("Planifier la suite", systemImage: "calendar.badge.plus")
                            Text("dès le \(Format.weekdayLong(plan.endDay.adding(days: 1)))")
                                .font(Theme.text(.caption))
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityIdentifier("planNextWeek")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .paperBackground()
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "La semaine", trailing: Format.range(plan, calendar: model.clock.calendar))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    if let targets = plan.targets {
                        WeekStat(title: "Cible par jour", value: Format.kcal(Double(targets.targetKcal))) {
                            Text("P \(targets.proteinG) · G \(targets.carbsG) · L \(targets.fatG)")
                                .font(Theme.text(.caption))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    if let preferences = allPreferences.first {
                        // Même ticket que l'onglet Courses : tous les repas, mangés compris (spec 019, FR-1904).
                        let summary = PlanStore.fullShoppingSummary(for: plan, in: context)
                        let days = plan.days.count
                        let status = BudgetStatus(cost: summary.weekCostEur, preferences: preferences, days: days)
                        WeekStat(title: "Ticket estimé", value: Format.euros(summary.checkoutEur)) {
                            BudgetBar(cost: summary.weekCostEur, preferences: preferences, days: days)
                                .frame(height: 6)
                                .padding(.vertical, 6)
                            Text(status.text).font(Theme.text(.caption, .bold)).foregroundStyle(status.ink)
                        }
                        .padding(.leading, plan.targets == nil ? 0 : 14)
                        .overlay(alignment: .leading) {
                            if plan.targets != nil { Rectangle().fill(Theme.line).frame(width: 1) }
                        }
                    }
                }
                if !plan.prepSessions.isEmpty {
                    Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 12)
                    NavigationLink {
                        PrepSessionView(sessions: plan.prepSessions, startDay: plan.startDay)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "frying.pan")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.wheatInk)
                                .frame(width: 32, height: 32)
                                .background(Theme.wheat, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .accessibilityHidden(true)
                            Text("\(plan.prepSessions.count) session(s) de batch cooking")
                                .font(Theme.text(.subheadline, .semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(Theme.ink)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .card(padding: 16, radius: 22)
        }
    }
}

/// Chiffre clé de la carte semaine : libellé, valeur, détail.
private struct WeekStat<Detail: View>: View {
    let title: LocalizedStringKey
    let value: String
    @ViewBuilder let detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Theme.text(.footnote, .medium)).foregroundStyle(Theme.muted)
            Text(value)
                .font(Theme.display(22, .heavy, relativeTo: .title3))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            detail
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Sélecteur des 7 jours.
struct DayStrip: View {
    let days: [DayPlan]
    let selected: Int?
    let today: LocalDay
    /// Préfixe des identifiants d'accessibilité (semaine ou journal).
    var idPrefix = "day-"
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
                            .fill(day.day == today ? (isSelected ? Theme.onAccent : Theme.accent) : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(isSelected ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Format.weekdayLong(day.day) + (day.day == today ? String(localized: ", aujourd'hui") : ""))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("\(idPrefix)\(day.offset)")
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
            WarningBadge(text: String(localized: "Hors cible \(Format.percent(deviation, signed: true))"))
        }
        // Spec 004 : glucides nettement au-dessus de la cible.
        if carbsDeviation > 0.15 {
            WarningBadge(
                text: String(localized: "Glucides \(Format.percent(carbsDeviation, signed: true))"), systemImage: "leaf.fill"
            )
        }
    }
}
