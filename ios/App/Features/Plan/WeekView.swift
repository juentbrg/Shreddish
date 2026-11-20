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
    @State private var path = NavigationPath()
    @State private var sharing = false

    private var activePlans: [WeeklyPlan] { plans.sorted { $0.startDay < $1.startDay } }

    private var shownPlan: WeeklyPlan? {
        activePlans.first { $0.id == selectedPlanID } ?? PlanStore.focusPlan(activePlans, today: model.clock.today)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let plan = shownPlan {
                    VStack(spacing: 0) {
                        if activePlans.count > 1 {
                            PlanSwitcher(plans: activePlans, selected: plan, today: model.clock.today) { selectedPlanID = $0 }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)
                        }
                        WeekPlanList(plan: plan, planNext: canPlanAfter(plan) ? { showNewWeek = true } : nil)
                            .id(plan.id)
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
                        card: WeekShareCard(plan: plan, budget: allPreferences.first?.weeklyBudget ?? 0)
                    )
                }
            }
            .onAppear(perform: openDeepLink)
            .onChange(of: model.deepLink) { openDeepLink() }
            .sheet(isPresented: $showNewWeek) {
                NewWeekSheet(today: model.clock.today, activePlans: activePlans) { start, pantry, recipes in
                    showNewWeek = false
                    generate(from: start, pantry: pantry, recipes: recipes)
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

    /// Bouton « Planifier la suite » : seulement sous le dernier planning actif, s'il n'est pas terminé.
    private func canPlanAfter(_ plan: WeeklyPlan) -> Bool {
        model.hasAPIKey && !model.isBusy && plan.id == activePlans.last?.id && plan.endDay >= model.clock.today
    }

    private func generate(from start: LocalDay, pantry: [IngredientDTO], recipes: [SavedRecipe]) {
        guard let profile = profiles.first, let preferences = allPreferences.first else { return }
        let generator = model.generator
        let context = context
        let live = model.liveMealsHandler
        selectedPlanID = nil
        Task {
            await model.run("Préparation de ta semaine…", recipesIn: context) { () async throws(AIError) -> [ValidationIssue] in
                let warnings = try await generator.generateWeek(
                    profile: profile, preferences: preferences, startDay: start, pantry: pantry,
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
    let start: (LocalDay, [IngredientDTO], [SavedRecipe]) -> Void
    @Query(sort: \SavedRecipe.savedAt, order: .reverse) var savedRecipes: [SavedRecipe]
    @State private var startDay: LocalDay?
    /// Recettes sauvegardées à replacer (spec 014) ; par défaut celles mises en attente.
    @State private var pickedRecipes: Set<UUID>?
    /// Questionnaire facultatif : ingrédients à écouler (spec 013).
    @State private var hasPantry = false
    @State private var pantry: [PantryRow] = []

    private var chosen: LocalDay { startDay ?? defaultStart }

    /// Lendemain du dernier planning en cours, pour ne pas archiver la semaine en cours par erreur.
    private var followingDay: LocalDay? {
        guard let next = activePlans.map(\.endDay).max()?.adding(days: 1), next > today,
              next <= today.adding(days: 13) else { return nil }
        return next
    }

    private var defaultStart: LocalDay { followingDay ?? today }

    /// Le choix touche un planning en cours (archivé ou jours remplacés).
    private var replacesActivePlan: Bool {
        if chosen <= today { return !activePlans.isEmpty }
        return activePlans.contains { $0.contains(chosen) || $0.startDay > chosen }
    }

    /// Paquets entamés du dernier planning.
    private var suggestions: [IngredientDTO] {
        activePlans.max { $0.startDay < $1.startDay }?.leftovers ?? []
    }

    /// Raccourcis : suite du planning en cours, aujourd'hui, demain, prochain lundi, prochain dimanche.
    private var shortcuts: [(String, LocalDay)] {
        var items: [(String, LocalDay)] = followingDay.map { [("Suite du planning", $0)] } ?? []
        let others = [
            ("Aujourd'hui", today), ("Demain", today.adding(days: 1)),
            ("Lundi prochain", Format.next(weekday: 2, after: today)),
            ("Dimanche prochain", Format.next(weekday: 1, after: today)),
        ]
        for (label, day) in others where !items.contains(where: { $0.1 == day }) { items.append((label, day)) }
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
                        .font(Theme.text(.footnote, replacesActivePlan ? .semibold : .regular))
                        .foregroundStyle(replacesActivePlan ? Theme.tomato : Theme.muted)
                    PantryQuestion(hasPantry: $hasPantry, rows: $pantry, suggestions: suggestions)
                    if !savedRecipes.isEmpty {
                        RecipePicker(recipes: savedRecipes, picked: Binding(
                            get: { pickedRecipes ?? Set(savedRecipes.filter(\.isQueued).map(\.id)) },
                            set: { pickedRecipes = $0 }
                        ))
                    }
                }
                .padding(20)
            }
            .paperBackground()
            .navigationTitle("Planifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Générer") {
                        let picked = pickedRecipes ?? Set(savedRecipes.filter(\.isQueued).map(\.id))
                        start(chosen, hasPantry ? pantry.compactMap(\.ingredient) : [], savedRecipes.filter { picked.contains($0.id) })
                    }
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
            VStack(alignment: .leading, spacing: 10) {
                if let targets = plan.targets {
                    LabeledContent("Cible", value: Format.kcal(Double(targets.targetKcal)))
                }
                if let preferences = allPreferences.first {
                    WeekCostRow(summary: plan.shoppingSummary, preferences: preferences)
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
    let summary: ShoppingSummary
    let preferences: Preferences

    /// Coût réel de la semaine (ticket moins les restes qui se gardent), comparé au budget (spec 013).
    private var cost: Double { summary.weekCostEur }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Ticket estimé", value: Format.euros(summary.checkoutEur))
                .accessibilityIdentifier("weekCost")
            if summary.keptEur >= 0.5 {
                LabeledContent("Coût de la semaine", value: Format.euros(cost))
                Text("Ticket moins \(Format.euros(summary.keptEur)) de produits qui te resteront (riz, huile…)")
                    .font(Theme.text(.caption))
                    .foregroundStyle(Theme.muted)
            }
            if summary.wastedEur >= 0.5 {
                Text("Dont \(Format.euros(summary.wastedEur)) de restes à finir vite (paquets entamés)")
                    .font(Theme.text(.caption))
                    .foregroundStyle(Theme.tomato)
            }
            let budget = Format.euros(preferences.weeklyBudget)
            ProgressView(value: min(cost, preferences.budgetCeiling), total: max(preferences.budgetCeiling, 1))
                .tint(cost > preferences.weeklyBudget + 0.005 ? Theme.tomato : Theme.green)
            Text("Budget \(budget) · tolérance \(Format.percent(preferences.tolerance))")
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
