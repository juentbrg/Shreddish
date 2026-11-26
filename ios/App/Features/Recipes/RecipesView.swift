import ShreddishCore
import SwiftData
import SwiftUI

/// Recettes sauvegardées depuis les repas qui ont plu, à replacer dans une semaine suivante (spec 014).
struct RecipesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedRecipe.savedAt, order: .reverse) var recipes: [SavedRecipe]
    @State private var creating = false
    @State private var search = ""
    @State private var filter = RecipeFilter.all

    /// Recette perso vide (spec 017, FR-1705).
    static let blank = MealDTO(
        type: .lunch, name: "", ingredients: [], steps: [""], prepMinutes: 15, costEur: 0,
        kcal: 0, proteinG: 0, carbsG: 0, fatG: 0, prepSessionRef: nil, time: nil
    )

    var body: some View {
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    EmptyState(
                        title: "Aucune recette sauvegardée", systemImage: "bookmark",
                        message: "Un repas t'a plu ? Ouvre-le et touche le signet pour le garder ici, ou crée ta recette."
                    )
                    .paperBackground()
                } else {
                    list
                }
            }
            .navigationTitle("Recettes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Créer une recette", systemImage: "plus") { creating = true }
                        .accessibilityIdentifier("createRecipe")
                }
            }
            .sheet(isPresented: $creating) {
                MealEditView(meal: Self.blank, title: "Nouvelle recette") { meal in
                    context.insert(SavedRecipe(meal: meal, savedAt: model.clock.now))
                    try? context.save()
                }
            }
        }
    }

    private var filtered: [SavedRecipe] {
        let query = TextNormalizer.basic(search.trimmingCharacters(in: .whitespaces))
        return recipes.filter { recipe in
            filter.matches(recipe.type) && (query.isEmpty || TextNormalizer.basic(recipe.name).contains(query))
        }
    }

    private var list: some View {
        let queued = recipes.filter(\.isQueued).count
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let saved = recipes.count == 1
                    ? String(localized: "1 recette sauvegardée")
                    : String(localized: "\(recipes.count) recettes sauvegardées")
                Text(queued == 0 ? saved : String(localized: "\(saved) · \(queued) pour la semaine prochaine"))
                    .font(Theme.text(.subheadline))
                    .foregroundStyle(Theme.muted)
                searchField
                Picker("Moment du repas", selection: $filter) {
                    ForEach(RecipeFilter.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(filtered) { recipe in
                        NavigationLink {
                            SavedRecipeView(recipe: recipe)
                        } label: {
                            RecipeCard(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Retirer des recettes", systemImage: "trash", role: .destructive) {
                                context.delete(recipe)
                                try? context.save()
                            }
                        }
                        .accessibilityIdentifier("savedRecipe")
                    }
                    Button {
                        creating = true
                    } label: {
                        Label("Créer une recette", systemImage: "plus")
                            .labelStyle(VerticalLabelStyle())
                            .font(Theme.text(.subheadline, .bold))
                            .foregroundStyle(Theme.tomatoInk)
                            .frame(maxWidth: .infinity, minHeight: 150)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(Theme.muted.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Text("Dans une recette, « Pour la semaine prochaine » la propose en planifiant la suite.")
                    .font(Theme.text(.footnote))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .paperBackground()
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("Chercher une recette", text: $search)
                .font(Theme.text(.body))
                .submitLabel(.search)
                .accessibilityIdentifier("recipeSearch")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Theme.card, in: Capsule())
    }
}

/// Filtre des recettes par moment du repas.
enum RecipeFilter: CaseIterable {
    case all, morning, meals, snacks

    var label: LocalizedStringKey {
        switch self {
        case .all: "Toutes"
        case .morning: "Matin"
        case .meals: "Midi, soir"
        case .snacks: "Collations"
        }
    }

    func matches(_ type: MealType) -> Bool {
        switch self {
        case .all: true
        case .morning: type == .breakfast
        case .meals: type == .lunch || type == .dinner
        case .snacks: type == .snack
        }
    }
}

/// Icône au-dessus du titre.
struct VerticalLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 6) {
            configuration.icon.font(.title2)
            configuration.title
        }
    }
}

/// Carte d'une recette : bandeau teinté par moment du repas, macros et prix.
struct RecipeCard: View {
    let recipe: SavedRecipe

    private var macros: String {
        [("P", recipe.proteinG), ("G", recipe.carbsG), ("L", recipe.fatG)]
            .map { "\($0.0) \(Format.number($0.1, digits: 0))" }
            .joined(separator: " · ")
    }

    var body: some View {
        let colors = recipe.type.tileColors
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Image(systemName: recipe.type.symbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(colors.ink)
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .background(colors.background)
                    .accessibilityHidden(true)
                if recipe.isQueued {
                    Text("Semaine pro.")
                        .font(Theme.text(.caption2, .bold))
                        .foregroundStyle(Theme.paper)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.ink, in: Capsule())
                        .padding(8)
                        .accessibilityLabel("Pour la semaine prochaine")
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.name)
                    .font(Theme.text(.subheadline, .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text("\(Format.kcal(recipe.kcal)) · \(Format.euros(recipe.costEUR))")
                    .font(Theme.text(.caption))
                    .foregroundStyle(Theme.muted)
                Text(macros)
                    .font(Theme.text(.caption))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Recette sauvegardée : ingrédients, étapes, mise en attente pour la semaine suivante.
struct SavedRecipeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query var allPreferences: [Preferences]
    @Bindable var recipe: SavedRecipe
    @State private var confirmDelete = false
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                Toggle(isOn: $recipe.isQueued) {
                    Label("Pour la semaine prochaine", systemImage: "calendar.badge.plus")
                        .font(Theme.text(.body, .semibold))
                }
                .tint(Theme.accent)
                .card()
                .padding(.horizontal, 20)
                .accessibilityIdentifier("queueRecipe")
                IngredientGrid(ingredients: recipe.ingredients, owned: allPreferences.first?.supplementList ?? [])
                RecipeSteps(steps: recipe.steps)
                Button("Retirer des recettes", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .confirmationDialog("Retirer cette recette ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Retirer", role: .destructive) {
                            context.delete(recipe)
                            try? context.save()
                            dismiss()
                        }
                    }
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 28)
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: recipe.isQueued) { try? context.save() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Modifier", systemImage: "pencil") { editing = true }
                    .accessibilityIdentifier("editRecipe")
            }
        }
        .sheet(isPresented: $editing) {
            MealEditView(meal: recipe.dto, title: "Modifier la recette") { meal in
                recipe.apply(meal)
                try? context.save()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recipe.type.label)
                .font(Theme.text(.subheadline, .semibold))
                .foregroundStyle(recipe.type.tileColors.ink)
            Text(recipe.name)
                .font(Theme.display(30, .heavy, relativeTo: .largeTitle))
                .foregroundStyle(Theme.ink)
            FlowPills(items: ["\(recipe.prepMinutes) min", Format.euros(recipe.costEUR), Format.kcal(recipe.kcal)])
            Text(
                """
                    Protéines \(Format.grams(recipe.proteinG)) · Glucides \(Format.grams(recipe.carbsG)) · Lipides \
                    \(Format.grams(recipe.fatG))
                    """
            )
                .font(Theme.text(.footnote))
                .foregroundStyle(Theme.ink)
            Text("Quantités de la semaine où tu l'as sauvegardée ; ajustées à tes cibles quand elle revient.")
                .font(Theme.text(.caption))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32, style: .continuous)
                .fill(recipe.type.tileColors.background)
                .ignoresSafeArea(edges: .top)
        )
    }
}

/// Recettes sauvegardées à replacer dans la semaine (spec 014).
struct RecipePicker: View {
    let recipes: [SavedRecipe]
    @Binding var picked: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Recettes à replacer", trailing: picked.isEmpty ? nil : String(localized: "\(picked.count) choisie(s)"))
            Text("L'IA les place dans la semaine, quantités ajustées à tes cibles.")
                .font(Theme.text(.footnote))
                .foregroundStyle(Theme.muted)
            ForEach(recipes) { recipe in
                let isPicked = picked.contains(recipe.id)
                Button {
                    if isPicked { picked.remove(recipe.id) } else { picked.insert(recipe.id) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isPicked ? Theme.accent : Theme.muted)
                        MealTile(type: recipe.type)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipe.name).font(Theme.text(.subheadline, .semibold))
                            Text("\(recipe.type.label) · \(Format.kcal(recipe.kcal))").font(Theme.text(.caption))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .card()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isPicked ? .isSelected : [])
                .accessibilityIdentifier("pickRecipe")
            }
        }
    }
}
