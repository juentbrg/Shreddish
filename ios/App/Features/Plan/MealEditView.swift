import ShreddishCore
import SwiftData
import SwiftUI

/// Repas ou recette modifié par l'utilisateur (spec 017, FR-1705) : nom, ingrédients pris dans Ciqual,
/// quantités, étapes. Macros et coût recalculés sur l'appareil, sans IA.
struct MealEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query var allPreferences: [Preferences]
    let title: String
    let onSave: (MealDTO) -> Void

    @State private var draft: MealDTO
    @State private var searching = false
    /// Ingrédient dont l'aliment Ciqual est en cours de choix ; nil = ajout.
    @State private var replacing: Int?

    init(meal: MealDTO, title: String = "Modifier le repas", onSave: @escaping (MealDTO) -> Void) {
        _draft = State(initialValue: meal)
        self.title = title
        self.onSave = onSave
    }

    private var resolver: NutritionResolver {
        NutritionResolver(
            cache: model.generator.matchCache, supplements: allPreferences.first?.ownedSupplementDetails ?? []
        )
    }

    /// Repas recalculé : macros Ciqual et prix de la table.
    private var resolved: (meal: MealDTO, verified: Bool) { resolver.resolve(draft, keepCodes: true) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom du plat", text: $draft.name)
                        .accessibilityIdentifier("editMealName")
                    Picker("Type", selection: $draft.type) {
                        ForEach(MealType.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Stepper("\(draft.prepMinutes) min de préparation", value: $draft.prepMinutes, in: 0...180, step: 5)
                }
                ingredientsSection
                stepsSection
                totalsSection
            }
            .themedList()
            .navigationTitle(LocalizedStringKey(title))
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        var meal = resolved.meal
                        meal.name = meal.name.trimmingCharacters(in: .whitespaces)
                        meal.steps = meal.steps.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        onSave(meal)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.ingredients.isEmpty)
                    .accessibilityIdentifier("saveMealEdit")
                }
            }
            .sheet(isPresented: $searching) {
                FoodSearchView { food in pick(food) }
            }
        }
    }

    private var ingredientsSection: some View {
        Section {
            ForEach(draft.ingredients.indices, id: \.self) { index in
                IngredientEditRow(ingredient: $draft.ingredients[index]) {
                    replacing = index
                    searching = true
                }
            }
            .onDelete { draft.ingredients.remove(atOffsets: $0) }
            Button("Ajouter un ingrédient", systemImage: "plus") {
                replacing = nil
                searching = true
            }
            .accessibilityIdentifier("addIngredient")
        } header: {
            ListHeader {
                Text("Ingrédients")
            }
        } footer: {
            ListFooter {
                Text("Quantités pour ta portion, pesées crues. Touche un nom pour le choisir dans la table Ciqual.")
            }
        }
    }

    private var stepsSection: some View {
        Section {
            ForEach(draft.steps.indices, id: \.self) { index in
                TextField("Étape \(index + 1)", text: $draft.steps[index], axis: .vertical)
            }
            .onDelete { draft.steps.remove(atOffsets: $0) }
            .onMove { draft.steps.move(fromOffsets: $0, toOffset: $1) }
            Button("Ajouter une étape", systemImage: "plus") { draft.steps.append("") }
                .accessibilityIdentifier("addStep")
        } header: {
            ListHeader {
                Text("Préparation")
            }
        }
    }

    private var totalsSection: some View {
        let meal = resolved.meal
        return Section {
            LabeledContent("Calories", value: Format.kcal(meal.kcal))
                .accessibilityIdentifier("editMealKcal")
            MacroLine(macros: meal.macros)
            LabeledContent("Coût", value: Format.euros(meal.costEur))
        } header: {
            ListHeader {
                Text("Total recalculé")
            }
        } footer: {
            ListFooter {
                if !resolved.verified {
                    Text("Un ingrédient n'est pas reconnu : macros précédentes conservées. Choisis-le dans Ciqual.")
                }
            }
        }
    }

    private func pick(_ food: Food) {
        if let index = replacing, draft.ingredients.indices.contains(index) {
            draft.ingredients[index].name = food.name
            draft.ingredients[index].foodCode = food.code
        } else {
            draft.ingredients.append(IngredientDTO(
                name: food.name, quantity: 100, unit: MeasureUnit.g.rawValue,
                aisle: AisleClassifier.corrected(name: food.name, aisle: .autre), costEur: 0, foodCode: food.code
            ))
        }
    }
}

/// Ligne d'ingrédient : nom (choix Ciqual), quantité, unité, poids d'une pièce.
private struct IngredientEditRow: View {
    @Binding var ingredient: IngredientDTO
    let chooseFood: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: chooseFood) {
                HStack {
                    Text(ingredient.name).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.plain)
            HStack {
                TextField("Quantité", value: $ingredient.quantity, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: 90)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("quantity-\(ingredient.name)")
                Picker("Unité", selection: $ingredient.unit) {
                    Text("g").tag(MeasureUnit.g.rawValue)
                    Text("ml").tag(MeasureUnit.ml.rawValue)
                    Text("pièce").tag(MeasureUnit.piece.rawValue)
                }
                .pickerStyle(.segmented)
            }
            if ingredient.measureUnit == .piece {
                HStack {
                    Text("Poids d'une pièce").font(Theme.text(.footnote)).foregroundStyle(Theme.muted)
                    Spacer()
                    TextField("g", value: Binding(
                        get: { ingredient.pieceG ?? 0 }, set: { ingredient.pieceG = $0 > 0 ? $0 : nil }
                    ), format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 70)
                    .textFieldStyle(.roundedBorder)
                    Text("g").foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Recherche d'un aliment dans la table Ciqual (éditeur de repas, journal rapide).
struct FoodSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let onPick: (Food) -> Void

    var body: some View {
        NavigationStack {
            List(FoodSearch.search(query), id: \.code) { food in
                Button {
                    onPick(food)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.name).foregroundStyle(Theme.ink)
                        Text("\(Format.kcal(food.per100g.kcal)) · P \(Format.grams(food.per100g.proteinG)) pour 100 g")
                            .font(Theme.text(.caption))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .accessibilityIdentifier("food-\(food.code)")
            }
            .themedList()
            .overlay {
                if query.count < 2 {
                    ContentUnavailableView("Cherche un aliment", systemImage: "magnifyingglass",
                                           description: Text("Table Ciqual : plus de 3 000 aliments."))
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "ex. riz basmati")
            .navigationTitle("Aliment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            }
        }
    }
}
