import Foundation

// Types valeur échangés avec l'IA (contracts/ai-meal.schema.json). Propriétés camelCase,
// JSON snake_case via `AIResponseDecoder.decoder` / `.encoder`.

public struct IngredientDTO: Codable, Sendable, Equatable {
    public var name: String
    public var quantity: Double
    /// Brute telle que reçue ; `g`, `ml` ou `piece` après validation (research R11).
    public var unit: String
    public var aisle: Aisle
    public var costEur: Double
    /// Prix au kg (g), au litre (ml) ou à la pièce estimé pour l'enseigne et le secteur (spec 005).
    public var unitPriceEur: Double?

    public init(
        name: String, quantity: Double, unit: String, aisle: Aisle, costEur: Double, unitPriceEur: Double? = nil
    ) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.aisle = aisle
        self.costEur = costEur
        self.unitPriceEur = unitPriceEur
    }

    public var measureUnit: MeasureUnit? { MeasureUnit(rawValue: unit) }
}

public struct MealDTO: Codable, Sendable, Equatable {
    public var type: MealType
    public var name: String
    public var ingredients: [IngredientDTO]
    public var steps: [String]
    public var prepMinutes: Int
    public var costEur: Double
    public var kcal: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var prepSessionRef: Int?
    /// Heure conseillée « HH:mm » ; null si non fournie (spec 004).
    public var time: String?

    public init(
        type: MealType, name: String, ingredients: [IngredientDTO], steps: [String], prepMinutes: Int,
        costEur: Double, kcal: Double, proteinG: Double, carbsG: Double, fatG: Double, prepSessionRef: Int?,
        time: String? = nil
    ) {
        self.type = type
        self.name = name
        self.ingredients = ingredients
        self.steps = steps
        self.prepMinutes = prepMinutes
        self.costEur = costEur
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.prepSessionRef = prepSessionRef
        self.time = time
    }

    public var macros: MacroTotals {
        MacroTotals(kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
    }
}

public struct DayPlanDTO: Codable, Sendable, Equatable {
    /// 0 = jour de génération, jusqu'à 6.
    public var dayOffset: Int
    public var meals: [MealDTO]

    public init(dayOffset: Int, meals: [MealDTO]) {
        self.dayOffset = dayOffset
        self.meals = meals
    }
}

public struct PrepSessionDTO: Codable, Sendable, Equatable {
    public var index: Int
    public var dayOffset: Int
    public var title: String
    public var durationMinutes: Int
    public var steps: [String]

    public init(index: Int, dayOffset: Int, title: String, durationMinutes: Int, steps: [String]) {
        self.index = index
        self.dayOffset = dayOffset
        self.title = title
        self.durationMinutes = durationMinutes
        self.steps = steps
    }
}

public struct WeekPlanDTO: Codable, Sendable, Equatable {
    public var prepSessions: [PrepSessionDTO]
    public var days: [DayPlanDTO]

    public init(prepSessions: [PrepSessionDTO], days: [DayPlanDTO]) {
        self.prepSessions = prepSessions
        self.days = days
    }
}

// MARK: - Enveloppes de réponse

struct WeekPlanResponse: Decodable {
    var infeasible: String?
    var prepSessions: [PrepSessionDTO]
    var days: [DayPlanDTO]
}

struct DayPlanResponse: Decodable {
    var infeasible: String?
    var day: DayPlanDTO
}

struct MealReplacementResponse: Decodable {
    var infeasible: String?
    var meal: MealDTO
}

/// Champ `infeasible` seul : lu avant le décodage complet pour qu'une réponse « impossible »
/// (jours vides, repas absent) remonte la raison au lieu d'une erreur de format.
private struct InfeasibleProbe: Decodable {
    var infeasible: String?
}

public enum AIResponseDecoder {
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decodeWeek(_ data: Data) throws(AIError) -> WeekPlanDTO {
        let response: WeekPlanResponse = try decode(data)
        return WeekPlanDTO(prepSessions: response.prepSessions, days: response.days)
    }

    public static func decodeDay(_ data: Data) throws(AIError) -> DayPlanDTO {
        let response: DayPlanResponse = try decode(data)
        return response.day
    }

    public static func decodeMeal(_ data: Data) throws(AIError) -> MealDTO {
        let response: MealReplacementResponse = try decode(data)
        return response.meal
    }

    private static func decode<T: Decodable>(_ data: Data) throws(AIError) -> T {
        // Tirets cadratins jamais structurels en JSON : retirés de tout le texte généré.
        let data = String(data: data, encoding: .utf8).map { Data(TextNormalizer.withoutDashes($0).utf8) } ?? data
        if let probe = try? decoder.decode(InfeasibleProbe.self, from: data),
           let reason = probe.infeasible?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            throw .infeasible(reason)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw .invalidOutput(String(describing: error))
        }
    }
}
