import Foundation
import SwiftData

/// Graphe du planning, forme V7 à V10 figée (spec 017 ajoute `Meal.eatenFraction`). Ne jamais modifier.
extension SchemaV7 {
    static var planModels: [any PersistentModel.Type] {
        [
            SchemaV7.WeeklyPlan.self, SchemaV7.DayPlan.self, SchemaV7.Meal.self, SchemaV7.ExtraEntry.self,
            SchemaV7.ShoppingItem.self,
        ]
    }

    @Model
    public final class WeeklyPlan {
        @Attribute(.unique) public var id: UUID
        public var startDayKey: Int
        public var createdAt: Date
        public var targetsData: Data
        public var prepSessionsData: Data
        public var isCurrent: Bool
        public var pantryData: Data?
        @Relationship(deleteRule: .cascade, inverse: \SchemaV7.DayPlan.plan) public var days: [SchemaV7.DayPlan] = []
        @Relationship(deleteRule: .cascade, inverse: \SchemaV7.ShoppingItem.plan)
        public var shoppingItems: [SchemaV7.ShoppingItem] = []

        public init(startDayKey: Int, createdAt: Date) {
            id = UUID()
            self.startDayKey = startDayKey
            self.createdAt = createdAt
            targetsData = Data()
            prepSessionsData = Data()
            isCurrent = true
        }
    }

    @Model
    public final class DayPlan {
        public var dayKey: Int
        public var offset: Int
        public var plan: SchemaV7.WeeklyPlan?
        @Relationship(deleteRule: .cascade, inverse: \SchemaV7.Meal.day) public var meals: [SchemaV7.Meal] = []
        @Relationship(deleteRule: .cascade, inverse: \SchemaV7.ExtraEntry.day) public var extras: [SchemaV7.ExtraEntry] = []

        public init(dayKey: Int, offset: Int) {
            self.dayKey = dayKey
            self.offset = offset
        }
    }

    @Model
    public final class Meal {
        public var typeRaw: String
        public var name: String
        public var ingredientsData: Data
        public var steps: [String]
        public var prepMinutes: Int
        public var costEUR: Double
        public var kcal: Double
        public var proteinG: Double
        public var carbsG: Double
        public var fatG: Double
        public var prepSessionRef: Int?
        public var time: String?
        public var statusRaw: String
        public var statusChangedAt: Date?
        public var order: Int
        public var day: SchemaV7.DayPlan?

        public init(order: Int) {
            typeRaw = "lunch"
            name = ""
            ingredientsData = Data()
            steps = []
            prepMinutes = 0
            costEUR = 0
            kcal = 0
            proteinG = 0
            carbsG = 0
            fatG = 0
            statusRaw = "planned"
            self.order = order
        }
    }

    @Model
    public final class ExtraEntry {
        public var name: String
        public var quantityLabel: String?
        public var kcal: Double
        public var proteinG: Double
        public var carbsG: Double
        public var fatG: Double
        public var loggedAt: Date
        public var day: SchemaV7.DayPlan?

        public init(name: String, loggedAt: Date) {
            self.name = name
            kcal = 0
            proteinG = 0
            carbsG = 0
            fatG = 0
            self.loggedAt = loggedAt
        }
    }

    @Model
    public final class ShoppingItem {
        public var plan: SchemaV7.WeeklyPlan?
        public var name: String
        public var key: String
        public var totalQuantity: Double
        public var unitRaw: String
        public var aisleRaw: String
        public var costEUR: Double
        public var isChecked: Bool

        public init(name: String, key: String) {
            self.name = name
            self.key = key
            totalQuantity = 0
            unitRaw = "g"
            aisleRaw = "autre"
            costEUR = 0
            isChecked = false
        }
    }
}
