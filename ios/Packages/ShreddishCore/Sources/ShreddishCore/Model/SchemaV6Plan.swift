import Foundation
import SwiftData

/// Graphe du planning, forme V4 à V6 figée (spec 013 ajoute `WeeklyPlan.pantryData`). Ne jamais modifier.
extension SchemaV6 {
    static var planModels: [any PersistentModel.Type] {
        [
            SchemaV6.WeeklyPlan.self, SchemaV6.DayPlan.self, SchemaV6.Meal.self, SchemaV6.ExtraEntry.self,
            SchemaV6.ShoppingItem.self,
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
        @Relationship(deleteRule: .cascade, inverse: \SchemaV6.DayPlan.plan) public var days: [SchemaV6.DayPlan] = []
        @Relationship(deleteRule: .cascade, inverse: \SchemaV6.ShoppingItem.plan)
        public var shoppingItems: [SchemaV6.ShoppingItem] = []

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
        public var plan: SchemaV6.WeeklyPlan?
        @Relationship(deleteRule: .cascade, inverse: \SchemaV6.Meal.day) public var meals: [SchemaV6.Meal] = []
        @Relationship(deleteRule: .cascade, inverse: \SchemaV6.ExtraEntry.day) public var extras: [SchemaV6.ExtraEntry] = []

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
        public var day: SchemaV6.DayPlan?

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
        public var day: SchemaV6.DayPlan?

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
        public var plan: SchemaV6.WeeklyPlan?
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

/// Schéma V7 (spec 013) : ingrédients à écouler déclarés avant la génération, par planning.
public enum SchemaV7: VersionedSchema {
    public static let versionIdentifier = Schema.Version(7, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Profile.self, Preferences.self, WeeklyPlan.self, DayPlan.self, Meal.self,
            ExtraEntry.self, ShoppingItem.self, WeightEntry.self,
        ]
    }
}

/// Schéma V8 (spec 014) : recettes sauvegardées, modèles existants inchangés.
public enum SchemaV8: VersionedSchema {
    public static let versionIdentifier = Schema.Version(8, 0, 0)

    public static var models: [any PersistentModel.Type] { SchemaV7.models + [SavedRecipe.self] }
}
