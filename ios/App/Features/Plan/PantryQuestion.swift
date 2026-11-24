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
    /// Proposé par l'application (reste, repas non mangé) : coché ou décoché, jamais supprimé.
    var isSuggested = false
    var isSelected = true

    init(name: String = "", quantity: String = "", unit: MeasureUnit = .g, foodCode: Int? = nil, pieceG: Double? = nil) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.foodCode = foodCode
        self.pieceG = pieceG
    }

    init(_ ingredient: IngredientDTO) {
        self.init(
            // Sans séparateur de milliers : « 1000 » se relit, « 1 000 » ou « 1,000 » non.
            name: ingredient.name, quantity: String(Int(ingredient.quantity.rounded())),
            unit: ingredient.measureUnit ?? .g, foodCode: ingredient.foodCode, pieceG: ingredient.pieceG
        )
        isSuggested = true
    }

    var ingredient: IngredientDTO? {
        let name = name.trimmingCharacters(in: .whitespaces)
        let digits = quantity.filter { !$0.isWhitespace && $0 != "\u{202F}" && $0 != "\u{00A0}" }
        let value = Double(digits.replacingOccurrences(of: ",", with: "."))
        guard isSelected, !name.isEmpty, let value, value > 0 else { return nil }
        return IngredientDTO(
            name: name, quantity: value, unit: unit.rawValue, aisle: .autre, costEur: 0, pieceG: pieceG, foodCode: foodCode
        )
    }
}

/// « As-tu des ingrédients à écouler ? » : facultatif ; oui, restes proposés à cocher puis saisies libres.
struct PantryQuestion: View {
    @Binding var hasPantry: Bool
    @Binding var rows: [PantryRow]
    let suggestions: [IngredientDTO]
    var suggestionsTitle: LocalizedStringKey = "Restes de ta dernière liste"

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
                if rows.contains(where: \.isSuggested) {
                    Text(suggestionsTitle)
                        .font(Theme.text(.subheadline, .semibold))
                    VStack(spacing: 0) {
                        ForEach($rows) { $row in
                            if row.isSuggested {
                                SuggestedPantryRow(row: $row)
                                if row.id != rows.last(where: \.isSuggested)?.id { Divider().overlay(Theme.line) }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    Text("Autres ingrédients")
                        .font(Theme.text(.subheadline, .semibold))
                        .padding(.top, 4)
                }
                ForEach($rows) { $row in
                    if !row.isSuggested { customRow($row) }
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

    private func customRow(_ row: Binding<PantryRow>) -> some View {
        HStack(spacing: 8) {
            TextField("Ingrédient", text: row.name)
                .textInputAutocapitalization(.sentences)
                .accessibilityIdentifier("pantryName")
            TextField("Qté", text: row.quantity)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
                .accessibilityIdentifier("pantryQuantity")
            Picker("Unité", selection: row.unit) {
                Text("g").tag(MeasureUnit.g)
                Text("ml").tag(MeasureUnit.ml)
                Text("pièce").tag(MeasureUnit.piece)
            }
            .labelsHidden()
            .fixedSize()
            Button("Retirer", systemImage: "xmark.circle.fill") { rows.removeAll { $0.id == row.wrappedValue.id } }
                .labelStyle(.iconOnly)
                .foregroundStyle(Theme.muted)
        }
        .font(Theme.text(.body))
        .card()
    }
}

/// Reste proposé : case à cocher, nom et quantité modifiable. Décoché, il reste en place, grisé.
private struct SuggestedPantryRow: View {
    @Binding var row: PantryRow

    var body: some View {
        HStack(spacing: 12) {
            Button {
                row.isSelected.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: row.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(row.isSelected ? Theme.success : Theme.muted)
                    Text(row.name)
                        .font(Theme.text(.subheadline, .semibold))
                        .foregroundStyle(row.isSelected ? Theme.ink : Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(row.isSelected ? .isSelected : [])
            .accessibilityHint("Coché : utilisé en priorité.")
            .accessibilityIdentifier("pantrySuggestion")
            TextField("Qté", text: $row.quantity)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .font(Theme.text(.subheadline))
                .disabled(!row.isSelected)
                .accessibilityLabel("Quantité de \(row.name)")
            Text(row.unit == .piece ? String(localized: "pièce") : row.unit.rawValue)
                .font(Theme.text(.subheadline))
                .foregroundStyle(Theme.muted)
        }
        .opacity(row.isSelected ? 1 : 0.6)
    }
}
