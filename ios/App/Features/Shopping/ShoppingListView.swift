import ShreddishCore
import SwiftData
import SwiftUI

/// Liste de courses agrégée par rayon depuis le planning courant (US5, FR-015 ; design « Marché »).
struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WeeklyPlan> { $0.isCurrent }, sort: \WeeklyPlan.createdAt, order: .reverse)
    var plans: [WeeklyPlan]
    @Query var allPreferences: [Preferences]
    /// Courses validées (spec 019) : observées pour rafraîchir l'écran à la validation.
    @Query var validations: [ShoppingValidation]
    @State private var selectedPlanID: UUID?
    /// Aliment tout juste banni et nombre de repas à venir qui en contiennent.
    @State private var banned: (food: String, meals: [Meal])?
    @Query var profiles: [Profile]
    /// Résultat de l'envoi vers Rappels.
    @State private var remindersMessage: String?
    @Environment(AppModel.self) private var model
    @State private var showHelp = false

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
            .toolbar {
                if let plan = shownPlan, !ShoppingExport.toBuy(plan).isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ShareLink(item: ShoppingExport.text(plan)) {
                                Label("Partager en texte", systemImage: "text.bubble")
                            }
                            Button("Envoyer vers Rappels", systemImage: "checklist") { sendToReminders(plan) }
                        } label: {
                            Label("Partager la liste", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("shareShoppingList")
                    }
                }
            }
            .alert(
                remindersMessage ?? "",
                isPresented: Binding(get: { remindersMessage != nil }, set: { if !$0 { remindersMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            }
            .alert(
                String(localized: "« \(banned?.food ?? "") » banni"),
                isPresented: Binding(get: { banned != nil }, set: { if !$0 { banned = nil } })
            ) {
                if let meals = banned?.meals, !meals.isEmpty {
                    Button(MealReplacement.label(count: meals.count)) {
                        MealReplacement.runAll(
                            meals: meals, profile: profiles.first, preferences: allPreferences.first, model: model, context: context
                        )
                    }
                    Button("Plus tard", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: {
                if let banned, !banned.meals.isEmpty {
                    Text("Plus jamais proposé dans tes plannings. \(banned.meals.count) repas à venir en contiennent.")
                } else {
                    Text("Plus jamais proposé dans tes plannings.")
                }
            }
        }
    }

    private func sendToReminders(_ plan: WeeklyPlan) {
        let lines = ShoppingExport.toBuy(plan).flatMap(\.items).map(ShoppingExport.line)
        Task {
            do {
                let added = try await ShoppingExport.sendToReminders(lines)
                remindersMessage = added == 0
                    ? String(localized: "Liste déjà à jour dans Rappels.")
                    : String(localized: "\(added) articles ajoutés à « Courses Shreddish » dans Rappels.")
            } catch ShoppingExport.RemindersError.denied {
                remindersMessage = String(localized: "Accès à Rappels refusé. Autorise-le dans Réglages → Shreddish.")
            } catch {
                remindersMessage = String(localized: "Envoi vers Rappels impossible.")
            }
        }
    }

    private func ban(_ food: String) {
        guard let preferences = allPreferences.first else { return }
        preferences.ban(food)
        try? context.save()
        banned = (food, PlanStore.upcomingMeals(containing: food, from: model.clock.today, in: context))
    }

    private func list(_ plan: WeeklyPlan) -> some View {
        let items = plan.shoppingItems
        let grouped = Dictionary(grouping: items, by: \.aisle)
        let aisles = grouped.keys.sorted { $0.sortIndex < $1.sortIndex }
        let checked = items.filter(\.isChecked).count
        // Coût de la semaine face au budget : tous les repas, mangés compris (spec 019).
        let summary = PlanStore.fullShoppingSummary(for: plan, in: context)
        let validation = validations.first { $0.planID == plan.id }
        let logged = plan.days.flatMap(\.meals).filter { $0.status != .planned }.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if activePlans.count > 1 {
                    WeekNavigator(weeks: activePlans, selected: plan, today: model.clock.today) { selectedPlanID = $0 }
                }
                subtitle(plan, count: items.count)
                ShoppingBudgetCard(
                    summary: summary, preferences: allPreferences.first,
                    progress: validation == nil
                        ? ShoppingProgress(remaining: plan.remainingShoppingEur, checked: checked, total: items.count) : nil
                )
                ShoppingStatus(plan: plan, validation: validation, logged: logged)
                ForEach(aisles, id: \.self) { aisle in
                    AisleCard(aisle: aisle, items: grouped[aisle] ?? [], toggle: { item in
                        item.isChecked.toggle()
                        PlanStore.rebuildFollowingShoppingList(after: plan, in: context)
                        try? context.save()
                    }, ban: ban)
                }
                // Tout coché : valider les courses, liste figée ensuite (spec 019).
                if validation == nil, !items.isEmpty, checked == items.count {
                    Button("Valider les courses", systemImage: "checkmark") {
                        ShoppingValidation.validate(plan, at: model.clock.now, in: context)
                    }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityIdentifier("validateShopping")
                }
                if checked > 0, validation == nil {
                    Button("Tout décocher") {
                        for item in items { item.isChecked = false }
                        PlanStore.rebuildFollowingShoppingList(after: plan, in: context)
                        try? context.save()
                    }
                    .buttonStyle(PillButtonStyle(prominent: false))
                }
                ReceiptSection(plan: plan, budget: allPreferences.first?.weeklyBudget ?? 0)
                    .id(plan.id)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        // Repas cochés ou décochés ailleurs (journal, montre) : liste recalculée à l'affichage (spec 019).
        .task(id: "\(plan.id)-\(logged)") {
            PlanStore.rebuildStaleShoppingList(for: plan, in: context)
            try? context.save()
        }
        .paperBackground()
    }

    /// Dates, nombre d'articles, aide derrière « i ».
    private func subtitle(_ plan: WeeklyPlan, count: Int) -> some View {
        HStack(spacing: 6) {
            Text("\(Format.range(plan, calendar: model.clock.calendar)) · \(count) articles · prix moyens")
                .font(Theme.text(.subheadline))
                .foregroundStyle(Theme.muted)
            Button {
                showHelp = true
            } label: {
                Image(systemName: "info.circle")
                    .font(Theme.text(.subheadline))
                    .foregroundStyle(Theme.muted)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comment sont calculés les prix")
            .popover(isPresented: $showHelp) {
                Text("Prix moyens en France, paquets entiers. Coche ce que tu as déjà. Appui long sur un article pour le bannir.")
                    .font(Theme.text(.subheadline))
                    .foregroundStyle(Theme.ink)
                    .padding()
                    .frame(idealWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
}

/// Courses validées (rouvrables), repas déjà mangés retirés, restes de la semaine d'avant déduits.
private struct ShoppingStatus: View {
    let plan: WeeklyPlan
    let validation: ShoppingValidation?
    let logged: Int
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model

    var body: some View {
        if let validation {
            let day = Format.weekdayLong(LocalDay(date: validation.validatedAt, calendar: model.clock.calendar))
            HStack {
                Label(
                    String(localized: "Courses validées le \(day)"),
                    systemImage: "checkmark.seal.fill"
                )
                .font(Theme.text(.subheadline, .semibold))
                .foregroundStyle(Theme.success)
                Spacer()
                Button("Rouvrir") { ShoppingValidation.reopen(plan, in: context) }
                    .buttonStyle(CompactButtonStyle(prominent: false))
                    .accessibilityIdentifier("reopenShopping")
            }
        } else if logged > 0 {
            Label(
                logged == 1
                    ? String(localized: "1 repas déjà mangé ou sauté retiré de la liste.")
                    : String(localized: "\(logged) repas déjà mangés ou sautés retirés de la liste."),
                systemImage: "fork.knife"
            )
            .font(Theme.text(.footnote))
            .foregroundStyle(Theme.muted)
            .accessibilityIdentifier("loggedMealsRemoved")
        }
        let carried = PlanStore.carriedStock(for: plan, in: context)
        if !carried.isEmpty {
            Label(
                String(localized: """
                    Restes déjà achetés la semaine d'avant déduits : \(carried.map(\.name).formatted(.list(type: .and))).
                    """),
                systemImage: "arrow.uturn.down"
            )
            .font(Theme.text(.footnote))
            .foregroundStyle(Theme.success)
            .accessibilityIdentifier("carriedStock")
        }
    }
}

/// Carte d'un rayon avec ses articles.
private struct AisleCard: View {
    let aisle: Aisle
    let items: [ShoppingItem]
    let toggle: (ShoppingItem) -> Void
    let ban: (String) -> Void

    var body: some View {
        let sorted = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(aisle.dotColor).frame(width: 10, height: 10)
                Text(aisle.label)
                    .font(Theme.text(.subheadline, .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(items.filter(\.isChecked).count) sur \(items.count)")
                    .font(Theme.text(.caption))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 8)
            ForEach(sorted) { item in
                ShoppingRow(item: item, toggle: { toggle(item) }, ban: ban)
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
    var ban: ((String) -> Void)?

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? Theme.success : Theme.muted)
                let packing = item.packing
                VStack(alignment: .leading, spacing: 2) {
                    // Ligne 1 : produit et prix ; ligne 2 : paquets et reste, sur toute la largeur.
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.name)
                            .font(Theme.text(.subheadline, .semibold))
                            .strikethrough(item.isChecked)
                            .foregroundStyle(item.isChecked ? Theme.muted : Theme.ink)
                        Spacer(minLength: 8)
                        Text(item.totalQuantity > 0 ? Format.euros(item.costEUR) : String(localized: "Déjà chez toi"))
                            .font(Theme.text(.subheadline, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(item.isChecked ? Theme.muted : Theme.ink)
                    }
                    if item.totalQuantity > 0 {
                        Text(Format.packing(packing, quantity: item.totalQuantity, unit: item.unit))
                            .font(Theme.text(.caption))
                            .monospacedDigit()
                            .foregroundStyle(Theme.muted)
                    }
                    if packing.leftover >= (item.unit == .piece ? 1 : 10) {
                        let rest = Format.quantity(packing.leftover, unit: item.unit)
                        Text(packing.perishable
                            ? String(localized: "Reste \(rest), à finir sous 3 jours")
                            : String(localized: "Reste \(rest) pour la suite"))
                            .font(Theme.text(.caption))
                            .foregroundStyle(packing.perishable ? Theme.tomato : Theme.muted)
                    }
                }
            }
            .frame(minHeight: 44)
            .padding(.vertical, 6)
            .opacity(item.isChecked ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let ban {
                Button("Ne plus jamais proposer", systemImage: "nosign", role: .destructive) { ban(item.name) }
            }
        }
        .accessibilityAction(named: "Ne plus jamais proposer") { ban?(item.name) }
        .accessibilityAddTraits(item.isChecked ? .isSelected : [])
        .accessibilityIdentifier("shopping-\(item.key)")
    }
}
