import ShreddishCore
import SwiftData
import SwiftUI

/// Ingrédient à écouler saisi avant la génération.
struct PantryRow: Identifiable, Equatable {
    let id = UUID()
    var name = ""
    var quantity = ""
    var unit: MeasureUnit = .g
    /// Code Ciqual d'un reste proposé par l'application.
    var foodCode: Int?
    var pieceG: Double?

    init(name: String = "", quantity: String = "", unit: MeasureUnit = .g, foodCode: Int? = nil, pieceG: Double? = nil) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.foodCode = foodCode
        self.pieceG = pieceG
    }

    init(_ ingredient: IngredientDTO) {
        self.init(
            name: ingredient.name, quantity: Format.number(ingredient.quantity, digits: 0),
            unit: ingredient.measureUnit ?? .g, foodCode: ingredient.foodCode, pieceG: ingredient.pieceG
        )
    }

    var ingredient: IngredientDTO? {
        let name = name.trimmingCharacters(in: .whitespaces)
        let value = Double(quantity.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        guard !name.isEmpty, let value, value > 0 else { return nil }
        return IngredientDTO(
            name: name, quantity: value, unit: unit.rawValue, aisle: .autre, costEur: 0, pieceG: pieceG, foodCode: foodCode
        )
    }
}

/// « As-tu des ingrédients à écouler ? » : facultatif ; oui, liste éditable avec les restes de la semaine passée.
struct PantryQuestion: View {
    @Binding var hasPantry: Bool
    @Binding var rows: [PantryRow]
    let suggestions: [IngredientDTO]
    var suggestionsTitle: LocalizedStringKey = "Restes de ta dernière liste"

    private var remainingSuggestions: [IngredientDTO] {
        suggestions.filter { suggestion in !rows.contains { $0.name == suggestion.name } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Des ingrédients à écouler ?")
            Picker("Des ingrédients à écouler ?", selection: $hasPantry) {
                Text("Non").tag(false)
                Text("Oui").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("hasPantry")
            if hasPantry {
                Text("Restes, conserves, féculents… L'IA s'en sert en priorité et ils sont déduits des courses.")
                    .font(Theme.text(.footnote))
                    .foregroundStyle(Theme.muted)
                if !remainingSuggestions.isEmpty {
                    Text(suggestionsTitle)
                        .font(Theme.text(.subheadline, .semibold))
                    suggestionButtons
                }
                ForEach($rows) { $row in
                    HStack(spacing: 8) {
                        TextField("Ingrédient", text: $row.name)
                            .textInputAutocapitalization(.sentences)
                            .accessibilityIdentifier("pantryName")
                        TextField("Qté", text: $row.quantity)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                            .accessibilityIdentifier("pantryQuantity")
                        Picker("Unité", selection: $row.unit) {
                            Text("g").tag(MeasureUnit.g)
                            Text("ml").tag(MeasureUnit.ml)
                            Text("pièce").tag(MeasureUnit.piece)
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button("Retirer", systemImage: "xmark.circle.fill") { rows.removeAll { $0.id == row.id } }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(Theme.muted)
                    }
                    .font(Theme.text(.body))
                    .card()
                }
                Button("Ajouter un ingrédient", systemImage: "plus") { rows.append(PantryRow()) }
                    .font(Theme.text(.subheadline, .semibold))
                    .accessibilityIdentifier("addPantry")
            }
        }
        .onChange(of: hasPantry) { _, isOn in
            if isOn, rows.isEmpty { rows = suggestions.isEmpty ? [PantryRow()] : suggestions.map(PantryRow.init) }
        }
    }

    private var suggestionButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(remainingSuggestions, id: \.name) { suggestion in
                    Button("+ \(suggestion.name)") { rows.append(PantryRow(suggestion)) }
                        .font(Theme.text(.subheadline))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(Theme.card, in: Capsule())
                        .buttonStyle(.plain)
                }
            }
        }
    }
}
