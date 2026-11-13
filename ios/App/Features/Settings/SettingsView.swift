import ShreddishCore
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var confirmErase = false

    var body: some View {
        List {
            Section {
                NavigationLink("Préférences repas") { PreferencesView() }
                    .accessibilityIdentifier("preferencesSettings")
            }
            Section {
                NavigationLink("Mon profil") { ProfileEditView() }
                NavigationLink("Ajuster les macros") { MacroSettingsView() }
            }
            Section {
                Button("Supprimer toutes mes données", role: .destructive) { confirmErase = true }
                    .accessibilityIdentifier("eraseAll")
            }
            Section("À propos") {
                Text("Pas un avis médical. Données sur cet iPhone ; seules cibles et préférences vont à OpenAI. "
                    + FoodCatalog.attribution + " " + PriceCatalog.attribution)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .themedList()
        .navigationTitle("Réglages")
        .confirmationDialog("Supprimer toutes tes données ?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Tout supprimer", role: .destructive, action: eraseAll)
        } message: {
            Text("Irréversible.")
        }
    }
}

extension SettingsView {
    /// Efface toutes les données locales (FR-211).
    private func eraseAll() {
        try? context.delete(model: ShoppingItem.self)
        try? context.delete(model: ExtraEntry.self)
        try? context.delete(model: Meal.self)
        try? context.delete(model: DayPlan.self)
        try? context.delete(model: WeeklyPlan.self)
        try? context.delete(model: WeightEntry.self)
        try? context.delete(model: Preferences.self)
        UserDefaultsFoodMatchCache().removeAll()
        try? context.delete(model: Profile.self)
        try? context.save()
        model.calibrationMessage = nil
        model.warningMessage = nil
        model.selectedTab = .week
    }
}
