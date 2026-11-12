import ShreddishCore
import SwiftData
import SwiftUI

/// Repas d'un jour, total face à la cible, remplacement et régénération (US2, US3).
struct DayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query var profiles: [Profile]
    @Query var allPreferences: [Preferences]
    let day: DayPlan
    @State private var confirmRegenerate = false

    private var isEditable: Bool { day.plan?.isCurrent == true }

    var body: some View {
        List {
            Section("Total du jour") {
                if let targets = day.plan?.targets {
                    let totals = day.plannedTotals
                    TargetGauge(title: "Calories", value: totals.kcal, target: Double(targets.targetKcal), format: Format.kcal)
                    TargetGauge(title: "Protéines", value: totals.proteinG, target: Double(targets.proteinG), format: Format.grams)
                    TargetGauge(title: "Glucides", value: totals.carbsG, target: Double(targets.carbsG), format: Format.grams)
                    TargetGauge(title: "Lipides", value: totals.fatG, target: Double(targets.fatG), format: Format.grams)
                }
                LabeledContent("Coût estimé", value: Format.euros(day.plannedCostEUR))
                DayBadges(day: day, targets: day.plan?.targets)
            }
            Section("Repas") {
                ForEach(day.sortedMeals) { meal in
                    NavigationLink {
                        MealDetailView(meal: meal)
                    } label: {
                        MealRow(meal: meal)
                    }
                    .swipeActions {
                        if isEditable {
                            Button("Remplacer", systemImage: "arrow.triangle.2.circlepath") { replace(meal) }
                                .tint(.accentColor)
                        }
                    }
                    .contextMenu {
                        if isEditable {
                            Button("Remplacer ce repas", systemImage: "arrow.triangle.2.circlepath") { replace(meal) }
                        }
                    }
                }
            }
        }
        .navigationTitle(Format.day(day.day, calendar: model.clock.calendar))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Régénérer", systemImage: "arrow.clockwise") { confirmRegenerate = true }
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("regenerateDay")
                }
            }
        }
        .confirmationDialog("Régénérer cette journée ?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
            Button("Régénérer la journée") { regenerate() }
        } message: {
            Text("Seule cette journée change. Les autres jours restent identiques.")
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

/// Remplacement d'un repas, partagé entre la journée et le détail du repas.
@MainActor
enum MealReplacement {
    static func run(meal: Meal, profile: Profile?, preferences: Preferences?, model: AppModel, context: ModelContext) {
        guard let profile, let preferences else { return }
        let generator = model.generator
        Task {
            await model.run("Recherche d'une alternative…") { () async throws(AIError) -> [ValidationIssue] in
                try await generator.replaceMeal(meal, profile: profile, preferences: preferences, in: context)
                return []
            }
        }
    }
}

struct MealRow: View {
    let meal: Meal

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: meal.type.symbol)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(meal.type.label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(meal.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 10) {
                    Label("\(meal.prepMinutes) min", systemImage: "timer")
                    Label(Format.euros(meal.costEUR), systemImage: "basket")
                    Text(Format.kcal(meal.kcal))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
