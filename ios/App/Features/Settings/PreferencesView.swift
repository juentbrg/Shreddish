import ShreddishCore
import SwiftData
import SwiftUI

/// Préférences de génération (FR-007, FR-008, FR-014 ; spec 003 : budget, magasin, allergies).
struct PreferencesView: View {
    @Environment(\.modelContext) private var context
    @Query var allPreferences: [Preferences]

    var body: some View {
        Form {
            if let preferences = allPreferences.first {
                MealsSection(preferences: preferences)
                BudgetSection(preferences: preferences)
                StoreSection(preferences: preferences)
                FoodsSections(preferences: preferences)
                ModelSection(preferences: preferences)
            }
        }
        .navigationTitle("Préférences repas")
        .keyboardDoneButton()
        .onAppear {
            if allPreferences.isEmpty { context.insert(Preferences()) }
        }
    }
}

private struct MealsSection: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Section {
            Stepper(
                "\(preferences.mealsPerDay) repas par jour", value: $preferences.mealsPerDay,
                in: Preferences.mealsPerDayRange
            )
            Stepper(
                "\(preferences.maxPrepMinutes) min max par repas", value: $preferences.maxPrepMinutes,
                in: Preferences.maxPrepMinutesRange, step: 5
            )
            Toggle("Batch cooking", isOn: $preferences.batchCooking)
        } header: {
            Text("Repas")
        } footer: {
            Text(
                "Collations incluses dans le nombre de repas : 4 = 3 repas + 1 collation. Batch cooking : "
                    + "1 à 2 sessions de préparation par semaine, réutilisées sur plusieurs repas."
            )
        }
    }
}

/// Budget courses de la semaine et dépassement toléré (FR-201, FR-202).
private struct BudgetSection: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Section {
            Stepper(
                "\(Format.euros(preferences.weeklyBudget)) par semaine",
                value: Binding(get: { preferences.weeklyBudget }, set: { preferences.weeklyBudget = $0 }),
                in: Preferences.weeklyBudgetRange, step: 5
            )
            .accessibilityIdentifier("weeklyBudget")
            Picker("Dépassement toléré", selection: Binding(get: { preferences.tolerance }, set: { preferences.tolerance = $0 })) {
                ForEach(Preferences.toleranceOptions, id: \.self) { option in
                    Text(option == 0 ? "Aucun" : "+\(Format.percent(option))").tag(option)
                }
            }
            .accessibilityIdentifier("budgetTolerance")
        } header: {
            Text("Budget courses")
        } footer: {
            Text(
                "Plafond : \(Format.euros(preferences.budgetCeiling)). Au-delà, le planning est refusé et regénéré ; "
                    + "entre budget et plafond, il est accepté et signalé. Prix estimés par l'IA, pas de prix réels."
            )
        }
    }
}

/// Magasin et disponibilité des ingrédients (FR-205, FR-206).
private struct StoreSection: View {
    @Bindable var preferences: Preferences

    private var storePlace: String {
        preferences.store == .generic ? "dans un supermarché classique" : "chez \(preferences.storeName)"
    }

    var body: some View {
        Section {
            Picker("Magasin", selection: Binding(get: { preferences.store }, set: { preferences.store = $0 })) {
                ForEach(GroceryStore.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .accessibilityIdentifier("store")
            if preferences.store == .other {
                TextField("Nom du magasin", text: Binding(
                    get: { preferences.customStoreName ?? "" }, set: { preferences.customStoreName = $0 }
                ))
            }
            Picker("Ingrédients", selection: Binding(get: { preferences.availability }, set: { preferences.availability = $0 })) {
                ForEach(IngredientAvailability.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .accessibilityIdentifier("availability")
        } header: {
            Text("Où tu fais tes courses")
        } footer: {
            Text(
                "\(preferences.availability.detail) L'IA choisit des produits vendus \(storePlace) "
                    + "et estime leurs prix, marque distributeur en priorité."
            )
        }
    }
}

private struct FoodsSections: View {
    @Bindable var preferences: Preferences

    var body: some View {
        FoodListSection(
            title: "Allergies", placeholder: "ex. arachide",
            items: Binding(get: { preferences.allergyList }, set: { preferences.allergyList = $0 }),
            footer: "Jamais proposés, ni en trace ni en dérivé. Un planning qui en contient est rejeté."
        )
        FoodListSection(
            title: "Aliments que tu n'aimes pas", placeholder: "ex. thon", items: $preferences.excludedFoods,
            footer: "Jamais proposés. Un planning qui en contient est rejeté."
        )
        FoodListSection(title: "Aliments appréciés", placeholder: "ex. poulet", items: $preferences.likedFoods, footer: nil)
        FoodListSection(
            title: "Équipement", placeholder: "ex. airfryer", items: $preferences.equipment,
            footer: "Plaques et four supposés disponibles."
        )
    }
}

private struct ModelSection: View {
    @Bindable var preferences: Preferences

    var body: some View {
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

extension IngredientAvailability {
    var label: String {
        switch self {
        case .everywhere: "Trouvables partout"
        case .supermarket: "Grand supermarché"
        case .specialty: "Magasins spécialisés OK"
        }
    }

    var detail: String {
        switch self {
        case .everywhere: "Ingrédients basiques, disponibles même en hard discount : rien de niche."
        case .supermarket: "Tout le rayon d'un grand supermarché, sans magasin spécialisé."
        case .specialty: "Produits bio ou spécialisés acceptés (tempeh, spiruline…)."
        }
    }
}
