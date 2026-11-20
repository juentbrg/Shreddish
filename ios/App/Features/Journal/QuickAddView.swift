import ShreddishCore
import SwiftData
import SwiftUI
import VisionKit

/// Journal rapide (spec 017, FR-1716) : favoris et récents en un toucher, recherche Ciqual, code-barres,
/// saisie libre en dernier recours.
struct QuickAddView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let day: DayPlan

    @State private var query = ""
    @State private var portion: PortionChoice?
    @State private var scanning = false
    @State private var lookingUp = false
    @State private var scanError: String?
    @State private var manual = false
    @State private var suggestions: [QuickFood] = []

    var body: some View {
        NavigationStack {
            List {
                if query.count < 2 {
                    Section {
                        if DataScannerViewController.isSupported {
                            Button("Scanner un code-barres", systemImage: "barcode.viewfinder") { scanning = true }
                                .accessibilityIdentifier("scanBarcode")
                        }
                        Button("Saisie libre", systemImage: "square.and.pencil") { manual = true }
                            .accessibilityIdentifier("manualExtra")
                        if lookingUp { ProgressView("Recherche du produit…") }
                        if let scanError {
                            Text(scanError).font(Theme.text(.footnote)).foregroundStyle(Theme.tomato)
                        }
                    }
                    if !suggestions.isEmpty {
                        ThemedSection("Favoris et récents") {
                            ForEach(suggestions) { food in
                                Button {
                                    portion = PortionChoice(food: food)
                                } label: {
                                    FoodRow(name: food.name, per100g: food.per100g, favorite: food.isFavorite)
                                }
                                .accessibilityIdentifier("quick-\(food.name)")
                            }
                        }
                    }
                } else {
                    ThemedSection("Table Ciqual") {
                        ForEach(FoodSearch.search(query), id: \.code) { food in
                            Button {
                                portion = PortionChoice(food: food)
                            } label: {
                                FoodRow(name: food.name, per100g: food.per100g, favorite: false)
                            }
                            .accessibilityIdentifier("food-\(food.code)")
                        }
                    }
                }
            }
            .themedList()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Chercher un aliment")
            .navigationTitle("Ajouter au journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
            .onAppear { suggestions = QuickLog.suggestions(in: context) }
            .sheet(item: $portion) { choice in
                PortionView(choice: choice) { grams, favorite in
                    let extra = QuickLog.log(
                        name: choice.name, per100g: choice.per100g, grams: grams, barcode: choice.barcode,
                        foodCode: choice.foodCode, to: day, at: model.clock.now, in: context
                    )
                    if let food = QuickLog.find(name: extra.name, barcode: choice.barcode, foodCode: choice.foodCode, in: context) {
                        food.isFavorite = favorite
                        try? context.save()
                    }
                    dismiss()
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $scanning) {
                BarcodeScanner { code in
                    scanning = false
                    Task { await lookUp(code) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $manual) {
                AddExtraView(day: day)
            }
        }
    }

    private func lookUp(_ barcode: String) async {
        scanError = nil
        if let known = QuickLog.find(name: "", barcode: barcode, foodCode: nil, in: context) {
            portion = PortionChoice(food: known)
            return
        }
        lookingUp = true
        defer { lookingUp = false }
        do {
            let product = try await model.packagedFoods.product(barcode: barcode)
            portion = PortionChoice(product: product)
        } catch .notFound {
            scanError = "Produit inconnu d'Open Food Facts. Cherche-le dans la table ou saisis-le."
        } catch .incomplete {
            scanError = "Valeurs nutritionnelles manquantes pour ce produit. Saisis-le à la main."
        } catch {
            scanError = "Pas de connexion : cherche l'aliment dans la table Ciqual."
        }
    }
}

/// Aliment choisi, en attente de sa portion.
struct PortionChoice: Identifiable {
    let id = UUID()
    let name: String
    let per100g: MacroTotals
    let grams: Double
    let barcode: String?
    let foodCode: Int?
    let isFavorite: Bool

    init(food: QuickFood) {
        name = food.name
        per100g = food.per100g
        grams = food.lastGrams
        barcode = food.barcode
        foodCode = food.foodCode
        isFavorite = food.isFavorite
    }

    init(food: Food) {
        name = food.name
        per100g = food.per100g
        grams = 100
        barcode = nil
        foodCode = food.code
        isFavorite = false
    }

    init(product: PackagedFood) {
        name = product.name
        per100g = product.per100g
        grams = product.servingG ?? 100
        barcode = product.barcode
        foodCode = nil
        isFavorite = false
    }
}

/// Portion en grammes, macros calculées, favori.
private struct PortionView: View {
    @Environment(\.dismiss) private var dismiss
    let choice: PortionChoice
    let onAdd: (Double, Bool) -> Void
    @State private var grams: Double
    @State private var favorite: Bool

    init(choice: PortionChoice, onAdd: @escaping (Double, Bool) -> Void) {
        self.choice = choice
        self.onAdd = onAdd
        _grams = State(initialValue: choice.grams)
        _favorite = State(initialValue: choice.isFavorite)
    }

    private var macros: MacroTotals {
        let factor = grams / 100
        return MacroTotals(
            kcal: choice.per100g.kcal * factor, proteinG: choice.per100g.proteinG * factor,
            carbsG: choice.per100g.carbsG * factor, fatG: choice.per100g.fatG * factor
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Quantité") {
                        HStack {
                            TextField("100", value: $grams, format: .number.precision(.fractionLength(0)))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("portionGrams")
                            Text("g").foregroundStyle(Theme.muted)
                        }
                    }
                    LabeledContent("Calories", value: Format.kcal(macros.kcal))
                    MacroLine(macros: macros)
                    Toggle("Favori", isOn: $favorite)
                } header: {
                    ListHeader {
                        Text(choice.name)
                    }
                }
            }
            .themedList()
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        onAdd(grams, favorite)
                        dismiss()
                    }
                    .disabled(grams <= 0)
                    .accessibilityIdentifier("addPortion")
                }
            }
        }
    }
}

private struct FoodRow: View {
    let name: String
    let per100g: MacroTotals
    let favorite: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).foregroundStyle(Theme.ink)
                Text("\(Format.kcal(per100g.kcal)) · P \(Format.grams(per100g.proteinG)) pour 100 g")
                    .font(Theme.text(.caption))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if favorite { Image(systemName: "star.fill").foregroundStyle(Theme.wheatInk) }
        }
    }
}

/// Lecteur de code-barres (VisionKit), appareil réel seulement.
private struct BarcodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced, isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for case let .barcode(code) in items {
                guard let value = code.payloadStringValue else { continue }
                done = true
                scanner.stopScanning()
                onCode(value)
                return
            }
        }
    }
}
