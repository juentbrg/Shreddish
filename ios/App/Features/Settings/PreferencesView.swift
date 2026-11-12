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
        .themedList()
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
        let budget = Binding(
            get: { preferences.weeklyBudget },
            set: { value in
                let range = Preferences.weeklyBudgetRange
                preferences.weeklyBudget = min(max(value, range.lowerBound), range.upperBound)
            }
        )
        Section {
            HStack {
                Text("Par semaine")
                Spacer()
                TextField("56", value: budget, format: .number.precision(.fractionLength(0...2)).locale(Format.locale))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    .font(.title3.bold().monospacedDigit())
                    .accessibilityIdentifier("weeklyBudget")
                Text("€")
            }
            Slider(value: budget, in: Preferences.weeklyBudgetRange, step: 1) {
                Text("Budget")
            } minimumValueLabel: {
                Text("20 €").font(.caption)
            } maximumValueLabel: {
                Text("300 €").font(.caption)
            }
            .accessibilityValue(Format.euros(preferences.weeklyBudget))
            HStack(spacing: 6) {
                ForEach([40.0, 50, 60, 80, 100], id: \.self) { preset in
                    let isSelected = preferences.weeklyBudget == preset
                    Button("\(Int(preset)) €") { budget.wrappedValue = preset }
                        .font(Theme.text(.subheadline, .semibold))
                        .foregroundStyle(isSelected ? Theme.onGreen : Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(isSelected ? Theme.green : Theme.paper, in: Capsule())
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("budgetPreset-\(Int(preset))")
                }
            }
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
                "Plafond : \(Format.euros(preferences.budgetCeiling)). Au-delà, l'IA refait un essai moins cher ; "
                    + "si ça dépasse encore, le planning est gardé et signalé. Prix estimés par l'IA, pas de prix réels."
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

    private var area: String {
        let city = preferences.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return city.isEmpty ? "en France" : "autour de \(city)"
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
            HStack {
                Text("Ville")
                TextField("ex. Toulouse", text: Binding(get: { preferences.city ?? "" }, set: { preferences.city = $0 }))
                    .multilineTextAlignment(.trailing)
                    .textContentType(.addressCity)
                    .accessibilityIdentifier("city")
            }
            Picker("Ingrédients", selection: Binding(get: { preferences.availability }, set: { preferences.availability = $0 })) {
                ForEach(IngredientAvailability.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .accessibilityIdentifier("availability")
        } header: {
            Text("Où tu fais tes courses")
        } footer: {
            Text(
                "\(preferences.availability.detail) L'IA choisit des produits vendus \(storePlace) \(area) "
                    + "et estime leur prix au kilo ou à la pièce pour ce secteur ; l'app en déduit le coût. "
                    + "Estimations, pas de prix relevés : aucune base de prix publique ne couvre les magasins."
            )
        }
    }
}

private struct FoodsSections: View {
    @Bindable var preferences: Preferences

    var body: some View {
        EditableListSection(
            title: "Allergies", placeholder: "ex. arachide",
            items: Binding(get: { preferences.allergyList }, set: { preferences.allergyList = $0 }),
            footer: "Jamais proposés, ni en trace ni en dérivé. Un planning qui en contient est rejeté.",
            suggestions: Suggestions.allergens
        )
        EditableListSection(
            title: "Aliments que tu n'aimes pas", placeholder: "ex. thon", items: $preferences.excludedFoods,
            footer: "Jamais proposés. Un planning qui en contient est rejeté.",
            suggestions: Suggestions.foods
        )
        EditableListSection(title: "Aliments appréciés", placeholder: "ex. poulet", items: $preferences.likedFoods, footer: nil,
            suggestions: Suggestions.foods
        )
        EditableListSection(
            title: "Équipement", placeholder: "ex. airfryer", items: $preferences.equipment,
            footer: "Plaques, casserole, poêle et four toujours supposés disponibles : riz et pâtes à la casserole.",
            suggestions: Suggestions.equipment
        )
        SupplementsSection(preferences: preferences)
    }
}

/// Compléments possédés et heure d'entraînement (spec 004, FR-301).
private struct SupplementsSection: View {
    @Bindable var preferences: Preferences

    var body: some View {
        EditableListSection(
            title: "Compléments possédés", placeholder: "ex. whey",
            items: Binding(get: { preferences.supplementList }, set: { preferences.supplementList = $0 }),
            footer: "Intégrés aux repas pour atteindre tes protéines, avec dose et moment de prise. "
                + "Comptés à 0 € et absents de la liste de courses.",
            suggestions: Suggestions.supplements
        )
        Section {
            Toggle("Heure fixe", isOn: Binding(
                get: { preferences.trainingTimeMinutes != nil },
                set: { preferences.trainingTimeMinutes = $0 ? 18 * 60 : nil }
            ))
            .accessibilityIdentifier("trainingTimeToggle")
            if let minutes = preferences.trainingTimeMinutes {
                DatePicker("Séance vers", selection: Binding(
                    get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now },
                    set: {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                        preferences.trainingTimeMinutes = (parts.hour ?? 18) * 60 + (parts.minute ?? 0)
                    }
                ), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Entraînement")
        } footer: {
            Text("Sert à placer la collation protéinée et la whey autour de ta séance. Sinon : fin de journée.")
        }
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
