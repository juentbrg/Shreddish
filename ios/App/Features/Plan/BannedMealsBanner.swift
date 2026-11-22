import ShreddishCore
import SwiftData
import SwiftUI

/// Repas à venir qui contiennent un aliment banni, avec un bouton pour tous les remplacer.
struct BannedMealsBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query var profiles: [Profile]
    @Query var allPreferences: [Preferences]
    /// Recalcule la liste après chaque remplacement ou bannissement.
    @Query(filter: #Predicate<WeeklyPlan> { $0.isCurrent }) var plans: [WeeklyPlan]

    var body: some View {
        let banned = allPreferences.first?.excludedFoods ?? []
        let meals = PlanStore.upcomingMeals(containingAnyOf: banned, from: model.clock.today, in: context)
        if !meals.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(meals.count == 1
                        ? String(localized: "1 repas à venir contient un aliment banni.")
                        : String(localized: "\(meals.count) repas à venir contiennent un aliment banni."))
                        .font(Theme.text(.subheadline, .semibold))
                        .foregroundStyle(Theme.ink)
                } icon: {
                    Image(systemName: "nosign").foregroundStyle(Theme.tomato)
                }
                Button {
                    MealReplacement.runAll(
                        meals: meals, profile: profiles.first, preferences: allPreferences.first, model: model, context: context
                    )
                } label: {
                    Label(MealReplacement.label(count: meals.count), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(PillButtonStyle())
                .disabled(model.isBusy)
                .accessibilityIdentifier("replaceBannedMeals")
            }
            .card()
        }
    }
}
