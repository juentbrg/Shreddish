import Foundation
import ShreddishCore

/// Réponses IA simulées pour les UI tests (argument `-uitest`), sur le modèle de Nowtick
/// `UITestSortTransport` : aucun appel réseau, réponses valides construites depuis la requête.
struct UITestAITransport: AITransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? AIConfig.baseURL
        let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        guard request.httpMethod == "POST", let body = request.httpBody,
              let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let inputText = root["input"] as? String,
              let input = (try? JSONSerialization.jsonObject(with: Data(inputText.utf8))) as? [String: Any] else {
            return (Data("{}".utf8), ok)
        }
        let text = try Self.response(for: input)
        let envelope: [String: Any] = [
            "status": "completed",
            "output": [["type": "message", "content": [["type": "output_text", "text": text]]]],
        ]
        return (try JSONSerialization.data(withJSONObject: envelope), ok)
    }

    static func response(for input: [String: Any]) throws -> String {
        let task = input["task"] as? String ?? "week"
        let targets = input["targets"] as? [String: Any] ?? [:]
        let preferences = input["preferences"] as? [String: Any] ?? [:]
        let mealsPerDay = preferences["meals_per_day"] as? Int ?? 4
        let target = MacroTotals(
            kcal: Double(targets["kcal"] as? Int ?? 2000), proteinG: Double(targets["protein_g"] as? Int ?? 150),
            carbsG: Double(targets["carbs_g"] as? Int ?? 200), fatG: Double(targets["fat_g"] as? Int ?? 60)
        )
        let types = mealTypes(count: mealsPerDay)
        let encoder = AIResponseDecoder.encoder

        func day(_ offset: Int, variant: String) -> DayPlanDTO {
            let share = 1 / Double(types.count)
            return DayPlanDTO(
                dayOffset: offset,
                meals: types.enumerated().map { index, type in
                    meal(type: type, share: share, target: target, variant: variant, draft: true, combo: offset * types.count + index)
                }
            )
        }

        let object: Encodable
        switch task {
        case "recipe":
            object = RecipeEnvelope(steps: [
                "Pèse les ingrédients.", "Cuis le riz 12 min à feu doux.", "Saisis le poulet 6 min.", "Sers chaud.",
            ])
        case "food_match":
            let items = input["items"] as? [[String: Any]] ?? []
            object = FoodMatchEnvelope(matches: items.map { item in
                let first = (item["candidates"] as? [[String: Any]])?.first?["code"] as? Int
                return FoodChoice(index: item["index"] as? Int ?? 0, code: first)
            })
        case "day":
            let offset = input["day_offset"] as? Int ?? 0
            object = DayEnvelope(day: day(offset, variant: "bis"))
        case "replace_meal":
            let type = MealType(rawValue: input["meal_type_to_replace"] as? String ?? "lunch") ?? .lunch
            object = MealEnvelope(meal: meal(type: type, share: 1 / Double(types.count), target: target, variant: "remplacé"))
        default:
            object = WeekEnvelope(days: (0..<7).map { day($0, variant: "J\($0 + 1)") })
        }
        return String(bytes: try encoder.encode(object), encoding: .utf8) ?? "{}"
    }

    static func mealTypes(count: Int) -> [MealType] {
        switch count {
        case 2: [.lunch, .dinner]
        case 3: [.breakfast, .lunch, .dinner]
        case 4: [.breakfast, .lunch, .snack, .dinner]
        default: [.breakfast, .lunch, .snack, .dinner, .snack]
        }
    }

    /// Protéine et féculent simulés, valeurs Ciqual pour 100 g (protéines, glucides, lipides).
    struct StubFood {
        let name: String
        let protein: Double
        let carbs: Double
        let fat: Double
        let price: Double
        let aisle: Aisle
    }

    static let proteins = [
        StubFood(name: "Poulet, filet sans peau cru", protein: 23.4, carbs: 0, fat: 1.5, price: 7, aisle: .viandePoisson),
        StubFood(name: "Thon, au naturel, appertisé, égoutté", protein: 26.8, carbs: 0, fat: 3.9, price: 9, aisle: .epicerie),
        StubFood(name: "Boeuf, steak haché 5% MG cru", protein: 21.9, carbs: 0.3, fat: 4.6, price: 9, aisle: .viandePoisson),
    ]
    static let starches = [
        StubFood(name: "Riz thaï ou basmati cru", protein: 7.1, carbs: 78.4, fat: 0.6, price: 2.5, aisle: .epicerie),
        StubFood(name: "Pâtes sèches, standard, crues", protein: 12, carbs: 72.7, fat: 1.6, price: 1.5, aisle: .epicerie),
        StubFood(name: "Semoule de blé dur, crue", protein: 11.8, carbs: 69.8, fat: 1.3, price: 1.8, aisle: .epicerie),
    ]

    /// Repas simulé : protéine, féculent et huile dosés avec les valeurs Ciqual pour tomber sur la part de cible ;
    /// `combo` varie protéine et féculent d'un repas à l'autre (au plus 2 fois la même association).
    static func meal(
        type: MealType, share: Double, target: MacroTotals, variant: String, draft: Bool = false, combo: Int = 0
    ) -> MealDTO {
        let protein = (target.proteinG * share).rounded()
        let carbs = (target.carbsG * share).rounded()
        let fat = (target.fatG * share).rounded()
        let meat = proteins[combo % proteins.count]
        let starch = starches[(combo / proteins.count) % starches.count]
        let starchG = (carbs / (starch.carbs / 100)).rounded()
        let meatG = max(0, ((protein - starchG * starch.protein / 100) / (meat.protein / 100)).rounded())
        let oil = max(0, (fat - meatG * meat.fat / 100 - starchG * starch.fat / 100).rounded())
        let names: [MealType: String] = [
            .breakfast: "Porridge fromage blanc", .lunch: "Poulet riz brocolis",
            .snack: "Skyr et amandes", .dinner: "Omelette pommes de terre",
        ]
        let times: [MealType: String] = [.breakfast: "08:00", .lunch: "12:30", .snack: "17:00", .dinner: "20:00"]
        return MealDTO(
            type: type, name: "\(names[type] ?? "Repas") \(variant)",
            ingredients: [
                IngredientDTO(
                    name: starch.name, quantity: starchG, unit: "g", aisle: starch.aisle, costEur: 0, unitPriceEur: starch.price
                ),
                IngredientDTO(name: meat.name, quantity: meatG, unit: "g", aisle: meat.aisle, costEur: 0, unitPriceEur: meat.price),
                IngredientDTO(name: "Huile de colza", quantity: oil, unit: "ml", aisle: .epicerie, costEur: 0, unitPriceEur: 3),
            ],
            steps: draft ? [] : ["Cuire le féculent.", "Saisir la protéine.", "Servir."], prepMinutes: 10, costEur: 1.45,
            kcal: 4 * protein + 4 * carbs + 9 * fat, proteinG: protein, carbsG: carbs, fatG: fat, prepSessionRef: nil,
            time: times[type]
        )
    }

    private struct WeekEnvelope: Encodable {
        var infeasible: String?
        var prepSessions: [PrepSessionDTO] = []
        var days: [DayPlanDTO]

        init(days: [DayPlanDTO]) { self.days = days }
    }

    private struct DayEnvelope: Encodable {
        var infeasible: String?
        var day: DayPlanDTO
    }

    private struct RecipeEnvelope: Encodable {
        var steps: [String]
    }

    private struct FoodMatchEnvelope: Encodable {
        var matches: [FoodChoice]
    }

    private struct MealEnvelope: Encodable {
        var infeasible: String?
        var meal: MealDTO
    }
}
