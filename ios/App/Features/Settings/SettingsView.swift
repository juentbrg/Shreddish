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
                NavigationLink("Abonnement") { PaywallView() }
                    .accessibilityIdentifier("subscriptionSettings")
            }
            Section {
                NavigationLink("Préférences repas") { PreferencesView() }
                    .accessibilityIdentifier("preferencesSettings")
                NavigationLink("Mon foyer") { HouseholdView() }
                    .accessibilityIdentifier("householdSettings")
                NavigationLink("Notifications") { NotificationSettingsView() }
                    .accessibilityIdentifier("notificationSettings")
                NavigationLink("Apple Santé") { HealthSettingsView() }
                    .accessibilityIdentifier("healthSettings")
                NavigationLink("Confidentialité") { PrivacySettingsView() }
                    .accessibilityIdentifier("privacySettings")
            }
            Section {
                NavigationLink("Modifier mon profil") { ProfileEditView() }
                NavigationLink("Ajuster les macros") { MacroSettingsView() }
            }
            Section {
                Button("Supprimer toutes mes données", role: .destructive) { confirmErase = true }
                    .accessibilityIdentifier("eraseAll")
                    .confirmationDialog("Supprimer toutes tes données ?", isPresented: $confirmErase, titleVisibility: .visible) {
                        Button("Tout supprimer", role: .destructive, action: eraseAll)
                    } message: {
                        Text("Irréversible.")
                    }
            }
            ThemedSection("À propos") {
                Text("Pas un avis médical. Données sur cet iPhone ; seules cibles et préférences vont à OpenAI. "
                    + FoodCatalog.attribution + " " + PriceCatalog.attribution)
                    .font(Theme.text(.footnote))
                    .foregroundStyle(Theme.muted)
            }
        }
        .themedList()
        .navigationTitle("Réglages")
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
        // Spec 017 : tout ce que l'app stocke, photos comprises (RGPD, FR-1714).
        try? context.delete(model: SavedRecipe.self)
        try? context.delete(model: QuickFood.self)
        try? context.delete(model: BodyMeasurement.self)
        try? context.delete(model: ProgressPhoto.self)
        try? context.delete(model: MemberWeight.self)
        try? context.delete(model: HouseholdMember.self)
        try? context.delete(model: ShoppingReceipt.self)
        try? context.delete(model: ShoppingValidation.self)
        UserDefaultsFoodMatchCache().removeAll()
        // Réglages stockés hors de la base : consentement IA, Santé, rappels, pesée remise à plus tard.
        // Accès gratuit déjà utilisé gardé : pas de nouvel essai en effaçant ses données.
        AIConsent.revoke()
        model.health.isEnabled = false
        model.notifications.settings = NotificationSettings()
        UserDefaults.standard.removeObject(forKey: NotificationService.settingsKey)
        UserDefaults.standard.removeObject(forKey: "weightRecalcDismissed")
        try? context.delete(model: Profile.self)
        try? context.save()
        model.calibrationMessage = nil
        model.warningMessage = nil
        model.undoableReplacement = nil
        model.selectedTab = .week
        // Rappels des repas supprimés retirés.
        Task { await model.notifications.reschedule() }
    }
}
