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
                NavigationLink {
                    APIKeyView()
                } label: {
                    LabeledContent("Clé API OpenAI", value: model.hasAPIKey ? "Enregistrée" : "Absente")
                }
                .accessibilityIdentifier("apiKeySettings")
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
            } footer: {
                Text("Profil, plannings, journal, courses, pesées et préférences. La clé API se supprime à part.")
            }
            Section("À propos") {
                Text("Shreddish est un outil personnel d'aide à l'organisation des repas, pas un avis médical ni diététique.")
                    .font(.footnote)
                Text(
                    "Données stockées sur cet iPhone seulement. Seules tes cibles et tes préférences repas "
                        + "sont envoyées à OpenAI, sans donnée d'identité."
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .themedList()
        .navigationTitle("Réglages")
        .confirmationDialog("Supprimer toutes tes données ?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Tout supprimer", role: .destructive, action: eraseAll)
        } message: {
            Text("Action irréversible. L'app revient à l'écran d'accueil.")
        }
    }
}

/// Saisie, test, remplacement et suppression de la clé (FR-019).
struct APIKeyView: View {
    @Environment(AppModel.self) private var model
    @State private var newKey = ""
    @State private var status: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section {
                if let key = currentKey {
                    LabeledContent("Clé actuelle", value: key.maskedKey)
                        .accessibilityIdentifier("maskedKey")
                } else {
                    Text("Aucune clé enregistrée.")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Stockée dans le trousseau de cet iPhone, jamais affichée en clair. Les appels sont facturés sur ton compte OpenAI.")
            }
            Section(currentKey == nil ? "Ajouter une clé" : "Remplacer la clé") {
                SecureField("sk-…", text: $newKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("apiKeyField")
                Button("Enregistrer") { save() }
                    .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let key = currentKey {
                Section {
                    Button {
                        Task { await test(key) }
                    } label: {
                        HStack {
                            Text("Tester la clé")
                            if isTesting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isTesting)
                    Button("Supprimer la clé", role: .destructive) {
                        model.keyStore.delete()
                        model.keyRevision += 1
                        status = "Clé supprimée."
                    }
                }
            }
            if let status {
                Section { Text(status).accessibilityIdentifier("keyStatus") }
            }
        }
        .themedList()
        .navigationTitle("Clé API")
    }

    private var currentKey: String? {
        _ = model.keyRevision
        return model.keyStore.read()
    }

    private func save() {
        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try model.keyStore.save(key)
            newKey = ""
            model.keyRevision += 1
            status = "Clé enregistrée."
        } catch {
            status = "Enregistrement impossible dans le trousseau."
        }
    }

    private func test(_ key: String) async {
        isTesting = true
        defer { isTesting = false }
        do {
            try await model.client.testKey(key)
            status = "Clé valide ✓"
        } catch {
            status = error.userMessage
        }
    }
}

extension SettingsView {
    /// Efface toutes les données locales (FR-211) ; la clé API reste dans le trousseau.
    private func eraseAll() {
        try? context.delete(model: ShoppingItem.self)
        try? context.delete(model: ExtraEntry.self)
        try? context.delete(model: Meal.self)
        try? context.delete(model: DayPlan.self)
        try? context.delete(model: WeeklyPlan.self)
        try? context.delete(model: WeightEntry.self)
        try? context.delete(model: Preferences.self)
        try? context.delete(model: Profile.self)
        try? context.save()
        model.calibrationMessage = nil
        model.warningMessage = nil
        model.selectedTab = .week
    }
}
