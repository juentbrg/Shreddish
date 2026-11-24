import ShreddishCore
import SwiftData
import SwiftUI

/// Détail d'un repas : ingrédients, étapes une par une ou toutes, temps, coût, macros (FR-010, design « Marché »).
struct MealDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query var profiles: [Profile]
    @Query var allPreferences: [Preferences]
    let meal: Meal
    @Query var savedRecipes: [SavedRecipe]
    @Query var members: [HouseholdMember]
    /// Quantités pour tout le foyer plutôt que pour ta portion (spec 017).
    @State private var forHousehold = false
    @State private var editing = false
    /// « Autre idée de repas » : confirmé avant de remplacer (repas déjà cuisiné, appui involontaire).
    @State private var confirmReplace = false
    /// Aliment tout juste banni : propose de remplacer ce repas.
    @State private var banned: String?
    /// Repas à venir qui contiennent l'aliment tout juste banni (celui-ci compris).
    @State private var bannedMeals: [Meal] = []

    private var owned: [String] { allPreferences.first?.supplementList ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                ingredients
                steps
                if meal.day?.plan?.isCurrent == true {
                    Button {
                        confirmReplace = true
                    } label: {
                        Label("Autre idée de repas", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("replaceMeal")
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .disabled(model.isBusy)
                    .confirmationDialog("Remplacer ce repas ?", isPresented: $confirmReplace, titleVisibility: .visible) {
                        Button("Remplacer", role: .destructive) {
                            MealReplacement.run(
                                meal: meal, profile: profiles.first, preferences: allPreferences.first, model: model, context: context
                            )
                            dismiss()
                        }
                    } message: {
                        Text("« \(meal.name) » et sa recette seront remplacés par une autre idée.")
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 28)
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) {
            MealEditView(meal: meal.dto) { dto in try? PlanStore.updateMeal(meal, with: dto, in: context) }
        }
        .toolbar {
            if meal.day?.plan?.isCurrent == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Modifier", systemImage: "pencil") { editing = true }
                        .disabled(meal.needsRecipe)
                        .accessibilityIdentifier("editMeal")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                let isSaved = savedRecipes.contains { RecipeBook.key($0.name) == RecipeBook.key(meal.name) }
                Button(isSaved ? String(localized: "Retirer des recettes") : String(localized: "Sauvegarder la recette"),
                    systemImage: isSaved ? "bookmark.fill" : "bookmark") {
                    RecipeBook.toggle(meal.dto, at: model.clock.now, in: context)
                }
                .disabled(meal.needsRecipe)
                .accessibilityIdentifier("saveRecipe")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text([meal.type.label, meal.time].compactMap(\.self).joined(separator: " · "))
                .font(Theme.text(.subheadline, .semibold))
                .foregroundStyle(meal.type.tileColors.ink)
            Text(meal.name)
                .font(Theme.display(30, .heavy, relativeTo: .largeTitle))
                .foregroundStyle(Theme.ink)
            FlowPills(items: [
                "\(meal.prepMinutes) min", Format.euros(meal.costEUR), Format.kcal(meal.kcal),
            ])
            Text("Protéines \(Format.grams(meal.proteinG)) · Glucides \(Format.grams(meal.carbsG)) · Lipides \(Format.grams(meal.fatG))")
                .font(Theme.text(.footnote))
                .foregroundStyle(Theme.ink)
            if let ref = meal.prepSessionRef,
               let session = meal.day?.plan?.prepSessions.first(where: { $0.index == ref }) {
                Label("Préparé pendant « \(session.title) »", systemImage: "frying.pan")
                    .font(Theme.text(.footnote))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32, style: .continuous)
                .fill(meal.type.tileColors.background)
                .ignoresSafeArea(edges: .top)
        )
    }

    @ViewBuilder private var ingredients: some View {
        let portions = Household.portions(members)
        if !members.isEmpty {
            Picker("Quantités", selection: $forHousehold) {
                Text("Ma portion").tag(false)
                Text("Foyer · \(Format.portion(portions))").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .accessibilityIdentifier("householdQuantities")
        }
        IngredientGrid(
            ingredients: forHousehold ? Household.scaled(meal.ingredients, portions: portions) : meal.ingredients,
            owned: owned
        ) { food in
            guard let preferences = allPreferences.first else { return }
            preferences.ban(food)
            try? context.save()
            bannedMeals = PlanStore.upcomingMeals(containing: food, from: model.clock.today, in: context)
            banned = food
        }
        .alert(
            String(localized: "« \(banned ?? "") » banni"),
            isPresented: Binding(get: { banned != nil }, set: { if !$0 { banned = nil } })
        ) {
            if !bannedMeals.isEmpty {
                Button(MealReplacement.label(count: bannedMeals.count)) {
                    MealReplacement.runAll(
                        meals: bannedMeals, profile: profiles.first, preferences: allPreferences.first, model: model, context: context
                    )
                    if bannedMeals.contains(where: { $0.persistentModelID == meal.persistentModelID }) { dismiss() }
                }
                .disabled(model.isBusy)
                Button("Plus tard", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text("Plus jamais proposé dans tes plannings. Liste dans Réglages → Préférences.")
        }
    }

    @ViewBuilder private var steps: some View {
        if meal.needsRecipe {
            pendingRecipe
        } else {
            RecipeSteps(steps: meal.steps)
        }
    }

    /// Recette pas encore rédigée : demandée en priorité (spec 010).
    private var pendingRecipe: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Préparation")
            HStack(spacing: 12) {
                if model.recipes.isPreparing(meal) { ProgressView() }
                Text(model.recipes.isPreparing(meal)
                    ? String(localized: "Recette en préparation…")
                    : String(localized: "Recette indisponible pour l'instant."))
                    .font(Theme.text(.body))
                    .foregroundStyle(Theme.muted)
                if !model.recipes.isPreparing(meal) {
                    Spacer()
                    Button("Réessayer") { model.recipes.prioritize(meal, in: context) }
                        .font(Theme.text(.subheadline, .semibold))
                }
            }
            .card()
            .accessibilityIdentifier("pendingRecipe")
        }
        .padding(.horizontal, 20)
        .task { model.recipes.prioritize(meal, in: context) }
    }
}

/// Ingrédients d'un repas sur deux colonnes.
struct IngredientGrid: View {
    let ingredients: [IngredientDTO]
    let owned: [String]
    /// Bannir un ingrédient (appui long) ; `nil` : pas de menu.
    var onBan: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Ce qu'il te faut")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(Array(ingredients.enumerated()), id: \.offset) { _, ingredient in
                    let isOwned = AIOutputValidator.isOwnedSupplement(ingredient.name, owned: owned)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ingredient.name)
                            .font(Theme.text(.subheadline, .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(
                            (WholeProduce.pieces(of: ingredient).map(Format.pieces)
                                ?? Format.quantity(ingredient.quantity, unit: ingredient.measureUnit ?? .g))
                                + " · " + (isOwned ? String(localized: "possédé") : Format.euros(ingredient.costEur))
                        )
                        .font(Theme.text(.caption))
                        .foregroundStyle(isOwned ? Theme.success : Theme.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .contextMenu {
                        if let onBan {
                            Button("Ne plus jamais proposer", systemImage: "nosign", role: .destructive) {
                                onBan(ingredient.name)
                            }
                        }
                    }
                    .accessibilityAction(named: "Ne plus jamais proposer") { onBan?(ingredient.name) }
                }
            }
            if onBan != nil {
                Text("Appui long sur un ingrédient pour ne plus jamais le voir dans tes plannings.")
                    .font(Theme.text(.caption))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 20)
    }
}

/// Étapes d'une recette : pas à pas en carrousel ou toutes (repas et recettes sauvegardées).
struct RecipeSteps: View {
    let steps: [String]
    @State private var step = 0
    @State private var showAllSteps = false
    /// Étape affichée dans le carrousel (défilement au doigt ou boutons).
    @State private var scrolledStep: Int?

    var body: some View {
        let all = steps
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title: showAllSteps
                    ? String(localized: "Préparation")
                    : String(localized: "Étape \(min(step, all.count - 1) + 1) sur \(all.count)"))
                Button(showAllSteps ? String(localized: "Pas à pas") : String(localized: "Tout voir")) { showAllSteps.toggle() }
                    .font(Theme.text(.subheadline, .semibold))
                    .accessibilityIdentifier("toggleSteps")
            }
            if showAllSteps {
                ForEach(Array(all.enumerated()), id: \.offset) { index, text in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(Theme.display(15, .bold, relativeTo: .headline))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 28, height: 28)
                            .background(Theme.accent, in: Circle())
                        Text(text)
                            .font(Theme.text(.body))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .card()
                }
            } else if !all.isEmpty {
                let index = min(step, all.count - 1)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(all.indices, id: \.self) { position in
                            Text(all[position])
                                .font(Theme.text(.title3))
                                .foregroundStyle(Theme.ink)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .card(padding: 18, radius: 22)
                                .containerRelativeFrame(.horizontal) { width, _ in width - 40 }
                                .id(position)
                        }
                    }
                    // Cartes à la hauteur de la plus longue étape.
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrolledStep)
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .padding(.horizontal, -20)
                .onChange(of: scrolledStep) { _, new in step = new ?? 0 }
                .accessibilityIdentifier("currentStep")
                HStack(spacing: 6) {
                    ForEach(all.indices, id: \.self) { dot in
                        Capsule()
                            .fill(dot == index ? Theme.accent : Theme.line)
                            .frame(width: dot == index ? 22 : 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
                HStack(spacing: 10) {
                    Button("Précédente") { goToStep(index - 1, count: all.count) }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .disabled(index == 0)
                    Button(index == all.count - 1 ? String(localized: "Terminé") : String(localized: "Étape suivante")) {
                        if index == all.count - 1 { showAllSteps = true } else { goToStep(index + 1, count: all.count) }
                    }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityIdentifier("nextStep")
                }
            }
        }
        .padding(.horizontal, 20)
        .animation(.snappy, value: step)
        .animation(.snappy, value: showAllSteps)
        .onChange(of: showAllSteps) { _, all in if !all { scrolledStep = step } }
    }

    /// Boutons : même défilement que le doigt.
    private func goToStep(_ target: Int, count: Int) {
        guard (0..<count).contains(target) else { return }
        withAnimation(.snappy) { scrolledStep = target }
    }
}

/// Pastilles sur plusieurs lignes si besoin.
struct FlowPills: View {
    let items: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { pills }
            VStack(alignment: .leading, spacing: 8) { pills }
        }
    }

    @ViewBuilder private var pills: some View {
        ForEach(items, id: \.self) { InfoPill(text: $0) }
    }
}
