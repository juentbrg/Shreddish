import ShreddishCore
import SwiftData
import SwiftUI

/// Contenu d'un jour : carte des macros, repas, régénération (US2, US3 ; design « Marché »).
struct DayContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query var profiles: [Profile]
    @Query var allPreferences: [Preferences]
    let day: DayPlan
    @State private var confirmRegenerate = false

    private var isEditable: Bool { day.plan?.isCurrent == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DayHeroCard(day: day, targets: day.plan?.targets)
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Au menu", trailing: "\(Format.euros(day.plannedCostEUR)) la journée")
                ForEach(day.sortedMeals) { meal in
                    NavigationLink {
                        MealDetailView(meal: meal)
                    } label: {
                        MealCard(meal: meal)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if isEditable {
                            Button("Remplacer ce repas", systemImage: "arrow.triangle.2.circlepath") { replace(meal) }
                        }
                    }
                }
            }
            if isEditable {
                Button {
                    confirmRegenerate = true
                } label: {
                    Label("Régénérer cette journée", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                .disabled(model.isBusy)
                .accessibilityIdentifier("regenerateDay")
            }
        }
        .confirmationDialog("Régénérer cette journée ?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
            Button("Régénérer la journée") { regenerate() }
        } message: {
            Text("Seule cette journée change.")
        }
    }

    private func regenerate() {
        guard let profile = profiles.first, let preferences = allPreferences.first else { return }
        let generator = model.generator
        let context = context
        let day = day
        Task {
            await model.run("Nouvelle journée en préparation…") { () async throws(AIError) -> [ValidationIssue] in
                try await generator.regenerateDay(day, profile: profile, preferences: preferences, in: context)
            }
        }
    }

    private func replace(_ meal: Meal) {
        MealReplacement.run(meal: meal, profile: profiles.first, preferences: allPreferences.first, model: model, context: context)
    }
}

/// Carte verte : kcal prévues et macros face aux cibles.
struct DayHeroCard: View {
    let day: DayPlan
    let targets: NutritionTargets?

    var body: some View {
        let totals = day.plannedTotals
        let deviation = Totals.deviation(totals, targetKcal: Double(targets?.targetKcal ?? 0))
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prévu ce jour")
                        .font(Theme.text(.footnote))
                        .opacity(0.85)
                    Text(Format.kcal(totals.kcal))
                        .font(Theme.display(38, .heavy, relativeTo: .largeTitle))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                Spacer()
                if targets != nil {
                    Text(Totals.isOffTarget(deviation) ? "Hors cible \(Format.percent(deviation, signed: true))" : "Dans la cible")
                        .font(Theme.text(.caption, .bold))
                        .foregroundStyle(Totals.isOffTarget(deviation) ? Theme.tomato : Theme.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            HStack(spacing: 8) {
                MacroTile(title: "Protéines", value: totals.proteinG, target: targets.map { Double($0.proteinG) })
                MacroTile(title: "Glucides", value: totals.carbsG, target: targets.map { Double($0.carbsG) })
                MacroTile(title: "Lipides", value: totals.fatG, target: targets.map { Double($0.fatG) })
            }
            DayBadges(day: day, targets: targets)
        }
        .foregroundStyle(Theme.onGreen)
        .padding(18)
        .background(Theme.green, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct MacroTile: View {
    let title: String
    let value: Double
    let target: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.text(.caption)).opacity(0.85)
            Text(Format.grams(value)).font(Theme.text(.headline, .bold))
            if let target {
                Text("cible \(Int(target.rounded()))").font(Theme.text(.caption2)).opacity(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.onGreen.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Carte d'un repas : icône, heure, nom, kcal, durée, coût.
struct MealCard: View {
    let meal: Meal

    var body: some View {
        let isSnack = meal.type == .snack
        HStack(spacing: 12) {
            MealTile(type: meal.type)
            VStack(alignment: .leading, spacing: 2) {
                Text([meal.time, meal.type.label].compactMap(\.self).joined(separator: " · "))
                    .font(Theme.text(.caption, isSnack ? .semibold : .regular))
                    .foregroundStyle(isSnack ? Theme.tomato : Theme.muted)
                Text(meal.name)
                    .font(Theme.text(.subheadline, .semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Text("\(Format.kcal(meal.kcal)) · \(meal.prepMinutes) min · \(Format.euros(meal.costEUR))")
                    .font(Theme.text(.caption))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            if meal.status == .eaten {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.green)
                    .accessibilityLabel("Mangé")
            }
        }
        .padding(10)
        .padding(.trailing, 2)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Remplacement d'un repas, partagé entre la journée et le détail du repas.
@MainActor
enum MealReplacement {
    static func run(meal: Meal, profile: Profile?, preferences: Preferences?, model: AppModel, context: ModelContext) {
        guard let profile, let preferences else { return }
        let generator = model.generator
        Task {
            await model.run("Recherche d'une alternative…") { () async throws(AIError) -> [ValidationIssue] in
                try await generator.replaceMeal(meal, profile: profile, preferences: preferences, in: context)
            }
        }
    }
}
