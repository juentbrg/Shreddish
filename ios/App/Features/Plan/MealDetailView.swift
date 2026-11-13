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
    @State private var step = 0
    @State private var showAllSteps = false

    private var owned: [String] { allPreferences.first?.supplementList ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                ingredients
                steps
                if meal.day?.plan?.isCurrent == true {
                    Button {
                        MealReplacement.run(
                            meal: meal, profile: profiles.first, preferences: allPreferences.first, model: model, context: context
                        )
                        dismiss()
                    } label: {
                        Label("Autre idée de repas", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .disabled(model.isBusy)
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 28)
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text([meal.type.label, meal.time].compactMap(\.self).joined(separator: " · "))
                .font(Theme.text(.subheadline, .semibold))
                .foregroundStyle(Theme.green)
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
                .fill(Theme.greenSoft)
                .ignoresSafeArea(edges: .top)
        )
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Ce qu'il te faut")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Array(meal.ingredients.enumerated()), id: \.offset) { _, ingredient in
                    let isOwned = AIOutputValidator.isOwnedSupplement(ingredient.name, owned: owned)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ingredient.name)
                            .font(Theme.text(.subheadline, .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(
                            Format.quantity(ingredient.quantity, unit: ingredient.measureUnit ?? .g)
                                + " · " + (isOwned ? "possédé" : Format.euros(ingredient.costEur))
                        )
                        .font(Theme.text(.caption))
                        .foregroundStyle(isOwned ? Theme.green : Theme.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder private var steps: some View {
        if meal.needsRecipe {
            pendingRecipe
        } else {
            recipeSteps
        }
    }

    /// Recette pas encore rédigée : demandée en priorité (spec 010).
    private var pendingRecipe: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Préparation")
            HStack(spacing: 12) {
                if model.recipes.isPreparing(meal) { ProgressView() }
                Text(model.recipes.isPreparing(meal) ? "Recette en préparation…" : "Recette indisponible pour l'instant.")
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

    @ViewBuilder private var recipeSteps: some View {
        let all = meal.steps
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title: showAllSteps ? "Préparation" : "Étape \(min(step, all.count - 1) + 1) sur \(all.count)")
                Button(showAllSteps ? "Pas à pas" : "Tout voir") { showAllSteps.toggle() }
                    .font(Theme.text(.subheadline, .semibold))
                    .accessibilityIdentifier("toggleSteps")
            }
            if showAllSteps {
                ForEach(Array(all.enumerated()), id: \.offset) { index, text in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(Theme.display(15, .bold, relativeTo: .headline))
                            .foregroundStyle(Theme.onGreen)
                            .frame(width: 28, height: 28)
                            .background(Theme.green, in: Circle())
                        Text(text)
                            .font(Theme.text(.body))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .card()
                }
            } else if !all.isEmpty {
                let index = min(step, all.count - 1)
                Text(all[index])
                    .font(Theme.text(.title3))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .card(padding: 18, radius: 22)
                    .accessibilityIdentifier("currentStep")
                HStack(spacing: 6) {
                    ForEach(all.indices, id: \.self) { dot in
                        Capsule()
                            .fill(dot == index ? Theme.green : Theme.line)
                            .frame(width: dot == index ? 22 : 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
                HStack(spacing: 10) {
                    Button("Précédente") { step = max(0, index - 1) }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .disabled(index == 0)
                    Button(index == all.count - 1 ? "Terminé" : "Étape suivante") {
                        if index == all.count - 1 { showAllSteps = true } else { step = index + 1 }
                    }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityIdentifier("nextStep")
                }
            }
        }
        .padding(.horizontal, 20)
        .animation(.snappy, value: step)
        .animation(.snappy, value: showAllSteps)
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
