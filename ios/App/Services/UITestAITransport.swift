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
            return DayPlanDTO(dayOffset: offset, meals: types.map { meal(type: $0, share: share, target: target, variant: variant) })
        }

        let object: Encodable
        switch task {
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

    static func meal(type: MealType, share: Double, target: MacroTotals, variant: String) -> MealDTO {
        let protein = (target.proteinG * share).rounded()
        let carbs = (target.carbsG * share).rounded()
        let fat = (target.fatG * share).rounded()
        let names: [MealType: String] = [
            .breakfast: "Porridge fromage blanc", .lunch: "Poulet riz brocolis",
            .snack: "Skyr et amandes", .dinner: "Omelette pommes de terre",
        ]
        return MealDTO(
            type: type, name: "\(names[type] ?? "Repas") \(variant)",
            ingredients: [
                IngredientDTO(name: "Riz basmati", quantity: 80, unit: "g", aisle: .epicerie, costEur: 0.25),
                IngredientDTO(name: "Blanc de poulet", quantity: 120, unit: "g", aisle: .viandePoisson, costEur: 1.2),
            ],
            steps: ["Cuire le riz.", "Saisir le poulet.", "Servir."], prepMinutes: 10, costEur: 1.45,
            kcal: 4 * protein + 4 * carbs + 9 * fat, proteinG: protein, carbsG: carbs, fatG: fat, prepSessionRef: nil
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

    private struct MealEnvelope: Encodable {
        var infeasible: String?
        var meal: MealDTO
    }
}
