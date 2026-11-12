import ShreddishCore
import SwiftData
import SwiftUI

/// Préférences de génération (FR-007, FR-008, FR-014).
struct PreferencesView: View {
    @Environment(\.modelContext) private var context
    @Query var allPreferences: [Preferences]

    var body: some View {
        Form {
            if let preferences = allPreferences.first {
                content(preferences)
            }
        }
        .navigationTitle("Préférences repas")
        .onAppear {
            if allPreferences.isEmpty { context.insert(Preferences()) }
        }
    }

    @ViewBuilder
    private func content(_ preferences: Preferences) -> some View {
        @Bindable var preferences = preferences
        Section {
            Stepper(
                "\(preferences.mealsPerDay) repas par jour", value: $preferences.mealsPerDay,
                in: Preferences.mealsPerDayRange
            )
            Stepper(
                "\(preferences.maxPrepMinutes) min max par repas", value: $preferences.maxPrepMinutes,
                in: Preferences.maxPrepMinutesRange, step: 5
            )
            Stepper(
                "Budget \(Format.euros(preferences.dailyBudgetEUR)) / jour", value: $preferences.dailyBudgetEUR,
                in: Preferences.dailyBudgetRange, step: 0.5
            )
        } footer: {
            Text("Collations incluses dans le nombre de repas : 4 = 3 repas + 1 collation.")
        }
        Section {
            Toggle("Batch cooking", isOn: $preferences.batchCooking)
        } footer: {
            Text("Activé : 1 à 2 sessions de préparation par semaine, réutilisées sur plusieurs repas.")
        }
        FoodListSection(
            title: "Aliments exclus / allergies", placeholder: "ex. thon", items: $preferences.excludedFoods,
            footer: "Jamais proposés. Un planning qui en contient est rejeté."
        )
        FoodListSection(title: "Aliments appréciés", placeholder: "ex. poulet", items: $preferences.likedFoods, footer: nil)
        FoodListSection(
            title: "Équipement", placeholder: "ex. airfryer", items: $preferences.equipment,
            footer: "Plaques et four supposés disponibles."
        )
        Section {
            TextField("Modèle", text: $preferences.aiModel)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Modèle par défaut") { preferences.aiModel = Preferences.defaultAIModel }
        } header: {
            Text("Modèle IA")
        } footer: {
            Text("Identifiant de modèle OpenAI compatible avec les sorties JSON structurées.")
        }
    }
}

struct FoodListSection: View {
    let title: String
    let placeholder: String
    @Binding var items: [String]
    let footer: String?
    @State private var draft = ""

    var body: some View {
        Section {
            ForEach(items, id: \.self) { Text($0) }
                .onDelete { items.remove(atOffsets: $0) }
            HStack {
                TextField(placeholder, text: $draft)
                    .onSubmit(add)
                Button("Ajouter", action: add)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text(title)
        } footer: {
            if let footer { Text(footer) }
        }
    }

    private func add() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if !items.contains(where: { TextNormalizer.basic($0) == TextNormalizer.basic(value) }) {
            items.append(value)
        }
        draft = ""
    }
}
