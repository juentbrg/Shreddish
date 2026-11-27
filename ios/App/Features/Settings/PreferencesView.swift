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
                FastingSection(preferences: preferences)
                DietSection(preferences: preferences)
                BudgetSection(preferences: preferences)
                StoreSection(preferences: preferences)
                FoodsSections(preferences: preferences)
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
            ListHeader {
                Text("Repas")
            }
        } footer: {
            ListFooter {
                Text(
                    "Collations incluses : 4 = 3 repas + 1 collation."
                )
            }
        }
    }
}

/// Régimes cumulables (spec 017, FR-1703).
private struct DietSection: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Section {
            ForEach(Diet.allCases, id: \.self) { diet in
                Toggle(diet.label, isOn: Binding(
                    get: { preferences.diets.contains(diet) },
                    set: { on in
                        var diets = preferences.diets.filter { $0 != diet }
                        if on { diets.append(diet) }
                        preferences.diets = Diet.allCases.filter(diets.contains)
                    }
                ))
                .accessibilityIdentifier("diet-\(diet.rawValue)")
            }
        } header: {
            ListHeader {
                Text("Régime")
            }
        } footer: {
            ListFooter {
                Text("Cumulables. Respectés dans chaque ingrédient, comme les allergies.")
            }
        }
    }
}

/// Jeûne intermittent (spec 015) : heures du premier et du dernier repas.
private struct FastingSection: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Section {
            Toggle("Jeûne intermittent", isOn: Binding(
                get: { preferences.eatingWindow != nil },
                set: { preferences.eatingWindow = $0 ? .default : nil }
            ))
            .accessibilityIdentifier("fastingToggle")
            if let window = preferences.eatingWindow {
                DatePicker("Premier repas", selection: time(window.startMinutes) { minutes in
                    EatingWindow(startMinutes: minutes, endMinutes: window.endMinutes)
                }, displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("fastingStart")
                DatePicker("Dernier repas", selection: time(window.endMinutes) { minutes in
                    EatingWindow(startMinutes: window.startMinutes, endMinutes: minutes)
                }, displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("fastingEnd")
            }
        } header: {
            ListHeader {
                Text("Jeûne")
            }
        } footer: {
            ListFooter {
                if let window = preferences.eatingWindow {
                    Text("""
                        Repas entre \(Format.clock(window.startMinutes)) et \(Format.clock(window.endMinutes)), \
                        \(Format.duration(window.fastingMinutes)) de jeûne. S'applique aux prochains plannings.
                        """)
                } else {
                    Text("Tous les repas dans une fenêtre horaire, par exemple de 12:00 à 19:30.")
                }
            }
        }
    }

    private func time(_ minutes: Int, update: @escaping (Int) -> EatingWindow) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                preferences.eatingWindow = update((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }
        )
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
                    .font(Theme.display(20, .bold, relativeTo: .title3).monospacedDigit())
                    .accessibilityIdentifier("weeklyBudget")
                Text("€")
            }
            Slider(value: budget, in: Preferences.weeklyBudgetRange, step: 1) {
                Text("Budget")
            } minimumValueLabel: {
                Text("20 €").font(Theme.text(.caption))
            } maximumValueLabel: {
                Text("300 €").font(Theme.text(.caption))
            }
            .accessibilityValue(Format.euros(preferences.weeklyBudget))
            HStack(spacing: 6) {
                ForEach([40.0, 50, 60, 80, 100], id: \.self) { preset in
                    let isSelected = preferences.weeklyBudget == preset
                    Button("\(Int(preset)) €") { budget.wrappedValue = preset }
                        .font(Theme.text(.subheadline, .semibold))
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(isSelected ? Theme.accent : Theme.paper, in: Capsule())
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("budgetPreset-\(Int(preset))")
                }
            }
            Picker("Dépassement toléré", selection: Binding(get: { preferences.tolerance }, set: { preferences.tolerance = $0 })) {
                ForEach(Preferences.toleranceOptions, id: \.self) { option in
                    Text(option == 0 ? String(localized: "Aucun") : "+\(Format.percent(option))").tag(option)
                }
            }
            .accessibilityIdentifier("budgetTolerance")
        } header: {
            ListHeader {
                Text("Budget courses")
            }
        } footer: {
            ListFooter {
                Text(
                    "Plafond \(Format.euros(preferences.budgetCeiling)). Prix moyens relevés en France (Open Prices)."
                )
            }
        }
    }
}

/// Disponibilité des ingrédients (FR-205).
private struct StoreSection: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Section {
            Picker("Ingrédients", selection: Binding(get: { preferences.availability }, set: { preferences.availability = $0 })) {
                ForEach(IngredientAvailability.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .accessibilityIdentifier("availability")
        } header: {
            ListHeader {
                Text("Ingrédients")
            }
        } footer: {
            ListFooter {
                Text(preferences.availability.detail)
            }
        }
    }
}

private struct FoodsSections: View {
    @Bindable var preferences: Preferences

    var body: some View {
        EditableListSection(
            title: "Allergies", placeholder: "ex. arachide",
            items: Binding(get: { preferences.allergyList }, set: { preferences.allergyList = $0 }),
            footer: "Jamais proposées, même en trace.",
            suggestions: Suggestions.allergens
        )
        EditableListSection(
            title: "Aliments bannis", placeholder: "ex. baguette", items: $preferences.excludedFoods,
            footer: "Jamais proposés. Ajoute-en aussi par appui long sur un ingrédient ou un article de courses.",
            suggestions: Suggestions.foods
        )
        EditableListSection(title: "Aliments appréciés", placeholder: "ex. poulet", items: $preferences.likedFoods, footer: nil,
            suggestions: Suggestions.foods
        )
        EditableListSection(
            title: "Équipement", placeholder: "ex. airfryer", items: $preferences.equipment,
            footer: "Plaques, casserole, poêle et four inclus.",
            suggestions: Suggestions.equipment
        )
        SupplementsSection(preferences: preferences)
    }
}

extension SupplementsSection {
    /// Résumé sous le nom du complément.
    /// « Chocolat · Dose de 30 g · … ».
    static func summary(_ info: SupplementInfo, name: String) -> String {
        let values = values(info, name: name)
        guard let flavor = info.flavor, !flavor.isEmpty else { return values }
        return flavor.capitalizedFirst + " · " + values
    }

    private static func values(_ info: SupplementInfo, name: String) -> String {
        switch info.resolvedKind(for: name) {
        case .macro:
            guard let serving = info.servingG else {
                return info.proteinPerServingG.map { "\(Format.number($0)) g de protéines par dose" }
                    ?? String(localized: "Préciser les valeurs par dose")
            }
            var parts = ["Dose de \(Format.number(serving)) g"]
            if let kcal = info.kcalPerServing { parts.append("\(Format.number(kcal, digits: 0)) kcal") }
            if let protein = info.proteinPerServingG { parts.append("P \(Format.number(protein)) g") }
            if let carbs = info.carbsPerServingG { parts.append("G \(Format.number(carbs)) g") }
            if let fat = info.fatPerServingG { parts.append("L \(Format.number(fat)) g") }
            return parts.joined(separator: " · ")
        case .dose:
            guard let amount = info.doseAmount else { return String(localized: "Préciser la dose") }
            let perDay = info.dosesPerDay ?? 1
            return String(localized: "\(Format.number(amount)) \((info.doseUnit ?? .g).label) par prise, \(perDay) fois par jour")
        }
    }
}

extension SupplementUnit {
    var label: String {
        switch self {
        case .g: "g"
        case .mg: "mg"
        case .µg: "µg"
        case .ml: "ml"
        case .gelule: String(localized: "gélule(s)")
        case .comprime: String(localized: "comprimé(s)")
        case .sachet: "sachet(s)"
        }
    }
}

/// Détail d'un complément selon sa nature (spec 007), enregistré à la saisie.
private struct SupplementInfoView: View {
    let name: String
    let preferences: Preferences
    @State private var info = SupplementInfo()

    var body: some View {
        let kind = info.resolvedKind(for: name)
        Form {
            Section {
                Picker("Type", selection: Binding(get: { kind }, set: { info.kind = $0 })) {
                    Text("Apporte des macros").tag(SupplementKind.macro)
                    Text("Dose simple").tag(SupplementKind.dose)
                }
                .accessibilityIdentifier("supplementKind")
                TextField("Goût (ex. chocolat, vanille)", text: Binding(
                    get: { info.flavor ?? "" },
                    set: { info.flavor = $0.isEmpty ? nil : $0 }
                ))
                .accessibilityIdentifier("supplementFlavor")
            } footer: {
                ListFooter {
                    Text(kind == .macro
                        ? String(localized: "Calories et macros comptées. Goût respecté dans les recettes.")
                        : String(localized: "Aucune calorie, prise placée dans un repas."))
                }
            }
            if kind == .macro {
                Section {
                    field("Taille d'une dose", value: $info.servingG, unit: "g", identifier: "servingSize")
                    field("Calories", value: $info.kcalPerServing, unit: "kcal", identifier: "kcalPerServing")
                    field("Protéines", value: $info.proteinPerServingG, unit: "g", identifier: "proteinPerServing")
                    field("Glucides", value: $info.carbsPerServingG, unit: "g", identifier: "carbsPerServing")
                    field("Lipides", value: $info.fatPerServingG, unit: "g", identifier: "fatPerServing")
                } header: {
                    ListHeader {
                        Text("Par dose")
                    }
                } footer: {
                    ListFooter {
                        Text("Valeurs de l'étiquette.")
                    }
                }
            } else {
                Section {
                    HStack {
                        Text("Par prise")
                        Spacer()
                        TextField("0", value: $info.doseAmount, format: .number.precision(.fractionLength(0...2)).locale(Format.locale))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 70)
                            .accessibilityIdentifier("doseAmount")
                        Picker("Unité", selection: Binding(get: { info.doseUnit ?? .g }, set: { info.doseUnit = $0 })) {
                            ForEach(SupplementUnit.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Stepper(
                        String(localized: "\(info.dosesPerDay ?? 1) prise(s) par jour"),
                        value: Binding(get: { info.dosesPerDay ?? 1 }, set: { info.dosesPerDay = $0 }),
                        in: 1...4
                    )
                } header: {
                    ListHeader {
                        Text("Dose")
                    }
                }
            }
        }
        .themedList()
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .onAppear { info = preferences.supplementInfo(for: name) }
        .onChange(of: info) { _, value in preferences.setSupplementInfo(value, for: name) }
    }

    private func field(_ title: String, value: Binding<Double?>, unit: String, identifier: String) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)).locale(Format.locale))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
                .accessibilityIdentifier(identifier)
            Text(unit).foregroundStyle(Theme.muted)
        }
    }
}

/// Compléments possédés et heure d'entraînement (spec 004, FR-301).
private struct SupplementsSection: View {
    @Bindable var preferences: Preferences

    var body: some View {
        EditableListSection(
            title: "Compléments possédés", placeholder: "ex. whey",
            items: Binding(get: { preferences.supplementList }, set: { preferences.supplementList = $0 }),
            footer: "Touche pour préciser. Comptés à 0 €, hors liste de courses.",
            suggestions: Suggestions.supplements,
            detail: { name in Self.summary(preferences.supplementInfo(for: name), name: name) },
            destination: { name in AnyView(SupplementInfoView(name: name, preferences: preferences)) }
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
            ListHeader {
                Text("Entraînement")
            }
        } footer: {
            ListFooter {
                Text("Pour placer la collation protéinée.")
            }
        }
    }
}

extension IngredientAvailability {
    var label: String {
        switch self {
        case .everywhere: String(localized: "Trouvables partout")
        case .supermarket: String(localized: "Grand supermarché")
        case .specialty: String(localized: "Magasins spécialisés OK")
        }
    }

    var detail: String {
        switch self {
        case .everywhere: String(localized: "Basiques, dispo même en hard discount.")
        case .supermarket: String(localized: "Rayon d'un grand supermarché.")
        case .specialty: String(localized: "Bio et spécialisé acceptés.")
        }
    }
}
