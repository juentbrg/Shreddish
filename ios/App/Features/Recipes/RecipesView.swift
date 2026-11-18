import ShreddishCore
import SwiftData
import SwiftUI

/// Recettes sauvegardées depuis les repas qui ont plu, à replacer dans une semaine suivante (spec 014).
struct RecipesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedRecipe.savedAt, order: .reverse) var recipes: [SavedRecipe]

    var body: some View {
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    ContentUnavailableView {
                        Label("Aucune recette sauvegardée", systemImage: "bookmark")
                    } description: {
                        Text("Un repas t'a plu ? Ouvre-le et touche le signet pour le garder ici.")
                    }
                    .paperBackground()
                } else {
                    list
                }
            }
            .navigationTitle("Recettes")
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Touche « Pour la semaine prochaine » dans une recette : elle sera proposée en planifiant la suite.")
                    .font(Theme.text(.footnote))
                    .foregroundStyle(Theme.muted)
                    .padding(.bottom, 4)
                ForEach(recipes) { recipe in
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
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .paperBackground()
    }
}

/// Carte d'une recette sauvegardée, même forme que la carte d'un repas.
struct RecipeCard: View {
    let recipe: SavedRecipe

    var body: some View {
        HStack(spacing: 12) {
            MealTile(type: recipe.type)
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.type.label)
                    .font(Theme.text(.caption))
                    .foregroundStyle(Theme.muted)
                Text(recipe.name)
                    .font(Theme.text(.subheadline, .semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Text("\(Format.kcal(recipe.kcal)) · \(recipe.prepMinutes) min · \(Format.euros(recipe.costEUR))")
                    .font(Theme.text(.caption))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            if recipe.isQueued {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(Theme.green)
                    .accessibilityLabel("Pour la semaine prochaine")
            }
        }
        .padding(10)
        .padding(.trailing, 2)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                Toggle(isOn: $recipe.isQueued) {
                    Label("Pour la semaine prochaine", systemImage: "calendar.badge.plus")
                        .font(Theme.text(.body, .semibold))
                }
                .tint(Theme.green)
                .card()
                .padding(.horizontal, 20)
                .accessibilityIdentifier("queueRecipe")
                IngredientGrid(ingredients: recipe.ingredients, owned: allPreferences.first?.supplementList ?? [])
                RecipeSteps(steps: recipe.steps)
                Button("Retirer des recettes", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 28)
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: recipe.isQueued) { try? context.save() }
        .confirmationDialog("Retirer cette recette ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Retirer", role: .destructive) {
                context.delete(recipe)
                try? context.save()
                dismiss()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recipe.type.label)
                .font(Theme.text(.subheadline, .semibold))
                .foregroundStyle(Theme.green)
            Text(recipe.name)
                .font(Theme.display(30, .heavy, relativeTo: .largeTitle))
                .foregroundStyle(Theme.ink)
            FlowPills(items: ["\(recipe.prepMinutes) min", Format.euros(recipe.costEUR), Format.kcal(recipe.kcal)])
            Text(
                "Protéines \(Format.grams(recipe.proteinG)) · Glucides \(Format.grams(recipe.carbsG))"
                    + " · Lipides \(Format.grams(recipe.fatG))"
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
                .fill(Theme.greenSoft)
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
            SectionTitle(title: "Recettes à replacer", trailing: picked.isEmpty ? nil : "\(picked.count) choisie(s)")
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
                            .foregroundStyle(isPicked ? Theme.green : Theme.muted)
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
