import Foundation
import ShreddishCore

/// Produit emballé trouvé par code-barres (Open Food Facts, licence ODbL), valeurs pour 100 g.
struct PackagedFood: Equatable, Sendable {
    let barcode: String
    let name: String
    let per100g: MacroTotals
    /// Portion indiquée sur l'emballage, en g.
    let servingG: Double?
}

/// Recherche d'un produit par code-barres. Seul le code-barres est envoyé (spec 017, FR-1716).
struct OpenFoodFactsClient: Sendable {
    static let attribution = "Produits emballés : Open Food Facts (ODbL)."
    let transport: any AITransport

    enum Failure: Error, Equatable {
        case notFound
        case incomplete
        case network
    }

    func product(barcode: String) async throws(Failure) -> PackagedFood {
        let digits = barcode.filter(\.isNumber)
        let fields = "product_name,product_name_fr,brands,nutriments,serving_quantity"
        guard !digits.isEmpty,
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json?fields=\(fields)") else {
            throw .notFound
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Shreddish/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
        let data: Data
        do {
            let (body, response) = try await transport.send(request)
            guard response.statusCode == 200 || response.statusCode == 404 else { throw Failure.network }
            data = body
        } catch {
            throw .network
        }
        return try Self.parse(data, barcode: digits)
    }

    static func parse(_ data: Data, barcode: String) throws(Failure) -> PackagedFood {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (json["status"] as? Int) == 1, let product = json["product"] as? [String: Any] else { throw .notFound }
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        func value(_ key: String) -> Double? {
            (nutriments[key] as? Double) ?? (nutriments[key] as? Int).map(Double.init) ?? (nutriments[key] as? String).flatMap(Double.init)
        }
        let protein = value("proteins_100g")
        let carbs = value("carbohydrates_100g")
        let fat = value("fat_100g")
        let kcal: Double
        if let energy = value("energy-kcal_100g") {
            kcal = energy
        } else if let protein, let carbs, let fat {
            kcal = 4 * protein + 4 * carbs + 9 * fat
        } else {
            throw .incomplete
        }
        let names = [product["product_name_fr"], product["product_name"]].compactMap { $0 as? String }.filter { !$0.isEmpty }
        let brand = (product["brands"] as? String)?.split(separator: ",").first.map(String.init)
        let name = [names.first ?? "Produit \(barcode)", brand].compactMap(\.self).joined(separator: " · ")
        return PackagedFood(
            barcode: barcode, name: name,
            per100g: MacroTotals(kcal: kcal, proteinG: protein ?? 0, carbsG: carbs ?? 0, fatG: fat ?? 0),
            servingG: (product["serving_quantity"] as? Double) ?? (product["serving_quantity"] as? String).flatMap(Double.init)
        )
    }
}
