import ShreddishCore
import SwiftUI

/// Suggestions d'autocomplétion des listes de préférences.
enum Suggestions {
    static let equipment = [
        "Micro-ondes", "Four", "Plaques de cuisson", "Airfryer", "Robot cuiseur", "Mixeur plongeant", "Blender",
        "Autocuiseur", "Cuiseur à riz", "Cuiseur vapeur", "Poêle", "Wok", "Casserole", "Plancha", "Grill",
        "Grille-pain", "Gaufrier", "Croque-monsieur", "Mijoteuse", "Robot pâtissier", "Balance de cuisine",
        "Mandoline", "Hachoir", "Boîtes de conservation",
    ]

    /// Les 14 allergènes à déclaration obligatoire dans l'UE.
    static let allergens = [
        "Gluten", "Crustacés", "Œufs", "Poisson", "Arachide", "Soja", "Lait", "Fruits à coque", "Céleri",
        "Moutarde", "Sésame", "Sulfites", "Lupin", "Mollusques",
    ]

    static let foods = [
        "Poulet", "Dinde", "Bœuf", "Steak haché", "Porc", "Jambon", "Saumon", "Thon", "Cabillaud", "Crevettes",
        "Œufs", "Tofu", "Lentilles", "Pois chiches", "Haricots rouges", "Riz", "Pâtes", "Pommes de terre",
        "Patate douce", "Quinoa", "Semoule", "Flocons d'avoine", "Pain complet", "Brocoli", "Courgette",
        "Épinards", "Haricots verts", "Carottes", "Poivron", "Champignons", "Tomate", "Avocat", "Banane",
        "Pomme", "Fruits rouges", "Skyr", "Fromage blanc", "Yaourt grec", "Fromage", "Lait", "Beurre de cacahuète",
        "Amandes", "Chocolat noir", "Coriandre", "Oignon", "Ail", "Champignons de Paris", "Aubergine", "Chou-fleur",
    ]
}

/// Liste modifiable : ajout avec autocomplétion, suppression visible sur chaque ligne (et balayage).
struct EditableListSection: View {
    let title: String
    let placeholder: String
    @Binding var items: [String]
    let footer: String?
    var suggestions: [String] = []
    @State private var draft = ""

    private var matches: [String] {
        let query = TextNormalizer.singular(draft)
        let added = Set(items.map(TextNormalizer.singular))
        return suggestions
            .filter { !added.contains(TextNormalizer.singular($0)) }
            .filter { query.isEmpty || TextNormalizer.singular($0).contains(query) }
            .prefix(query.isEmpty ? 8 : 12)
            .map { $0 }
    }

    var body: some View {
        Section {
            ForEach(items, id: \.self) { item in
                HStack {
                    Text(item)
                    Spacer()
                    DeleteRowButton(label: item) { remove(item) }
                }
            }
            .onDelete { items.remove(atOffsets: $0) }
            HStack {
                TextField(placeholder, text: $draft)
                    .onSubmit { add(draft) }
                    .accessibilityIdentifier("\(title)-field")
                Button("Ajouter") { add(draft) }
                    .buttonStyle(.borderless)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !matches.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(matches, id: \.self) { suggestion in
                            Button {
                                add(suggestion)
                            } label: {
                                Label(suggestion, systemImage: "plus")
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("suggestion-\(suggestion)")
                        }
                    }
                }
            }
        } header: {
            Text(title)
        } footer: {
            if let footer { Text(footer) }
        }
    }

    private func add(_ value: String) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if !items.contains(where: { TextNormalizer.basic($0) == TextNormalizer.basic(value) }) {
            items.append(value)
        }
        draft = ""
    }

    private func remove(_ item: String) {
        items.removeAll { $0 == item }
    }
}
