import ShreddishCore
import SwiftData
import SwiftUI

/// Contenu d'un jour : carte des macros, repas, régénération (US2, US3 ; design « Marché »).
struct DayContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query var profiles: [Profile]
    @Query var allPreferences: [Preferences]
    @Query var members: [HouseholdMember]
    let day: DayPlan
    @State private var confirmRegenerate = false

    private var isEditable: Bool { day.plan?.isCurrent == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DayHeroCard(day: day, targets: day.plan?.targets)
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(
                    title: "Au menu",
                    trailing: members.isEmpty
                        ? String(localized: "\(Format.euros(day.plannedCostEUR)) la journée")
                        : String(localized: "\(Format.euros(day.plannedCostEUR * Household.portions(members))) pour le foyer")
                )
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
            await model.run("Nouvelle journée en préparation…", recipesIn: context) { () async throws(AIError) -> [ValidationIssue] in
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
                        .font(Theme.text(.footnote, .medium))
                        .foregroundStyle(Theme.muted)
                    Text(Format.kcal(totals.kcal))
                        .font(Theme.display(38, .heavy, relativeTo: .largeTitle))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if targets != nil {
                    Text(Totals.isOffTarget(deviation)
                        ? String(localized: "Hors cible \(Format.percent(deviation, signed: true))")
                        : String(localized: "Dans la cible"))
                        .font(Theme.text(.caption, .bold))
                        .foregroundStyle(Totals.isOffTarget(deviation) ? Theme.tomatoInk : Theme.success)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Totals.isOffTarget(deviation) ? Theme.tomatoSoft : Theme.successSoft,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
            }
            MacroSplitBar(proteinG: totals.proteinG, carbsG: totals.carbsG, fatG: totals.fatG)
            HStack(spacing: 8) {
                MacroTile(
                    title: "Protéines", value: totals.proteinG, target: targets.map { Double($0.proteinG) },
                    palette: Theme.protein
                )
                MacroTile(
                    title: "Glucides", value: totals.carbsG, target: targets.map { Double($0.carbsG) }, palette: Theme.carbs
                )
                MacroTile(title: "Lipides", value: totals.fatG, target: targets.map { Double($0.fatG) }, palette: Theme.fat)
            }
            DayBadges(day: day, targets: targets)
        }
        .foregroundStyle(Theme.ink)
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct MacroTile: View {
    let title: String
    let value: Double
    let target: Double?
    let palette: MacroPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title)).font(Theme.text(.caption, .bold)).foregroundStyle(palette.ink)
            Text(Format.grams(value)).font(Theme.text(.headline, .bold)).foregroundStyle(Theme.ink)
            if let target {
                Text("cible \(Int(target.rounded()))").font(Theme.text(.caption2, .medium)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(palette.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Répartition des calories entre protéines, glucides et lipides (4 / 4 / 9 kcal par gramme).
struct MacroSplitBar: View {
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    var body: some View {
        let parts = [(proteinG * 4, Theme.protein.bar), (carbsG * 4, Theme.carbs.bar), (fatG * 9, Theme.fat.bar)]
        let total = max(parts.reduce(0) { $0 + $1.0 }, 1)
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(parts.indices, id: \.self) { index in
                    Capsule()
                        .fill(parts[index].1)
                        .frame(width: max(0, (proxy.size.width - 6) * parts[index].0 / total))
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// Carte d'un repas : icône, heure, nom, kcal, durée, coût.
struct MealCard: View {
    let meal: Meal

    var body: some View {
        HStack(spacing: 12) {
            MealTile(type: meal.type)
            VStack(alignment: .leading, spacing: 2) {
                Text([meal.time, meal.type.label].compactMap(\.self).joined(separator: " · "))
                    .font(Theme.text(.caption, .semibold))
                    .foregroundStyle(meal.type.tileColors.ink)
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
                    .foregroundStyle(Theme.success)
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

    /// « Remplacer ce repas » ou « Remplacer les 3 repas ».
    static func label(count: Int) -> String {
        count == 1 ? String(localized: "Remplacer ce repas") : String(localized: "Remplacer les \(count) repas")
    }

    /// Remplace un à un les repas qui contiennent un aliment banni.
    static func runAll(meals: [Meal], profile: Profile?, preferences: Preferences?, model: AppModel, context: ModelContext) {
        guard let profile, let preferences, !meals.isEmpty else { return }
        let generator = model.generator
        let total = meals.count
        Task {
            await model.run(String(localized: "Remplacement de \(total) repas…")) { () async throws(AIError) -> [ValidationIssue] in
                var warnings: [ValidationIssue] = []
                for (index, meal) in meals.enumerated() where !meal.isDeleted && meal.day != nil {
                    model.busyMessage = String(localized: "Remplacement du repas \(index + 1) sur \(total)…")
                    warnings += try await generator.replaceMeal(meal, profile: profile, preferences: preferences, in: context)
                }
                return warnings
            }
        }
    }
}
