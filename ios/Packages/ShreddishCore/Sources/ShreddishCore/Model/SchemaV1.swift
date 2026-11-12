import Foundation
import SwiftData

/// Schéma V1, figé tel qu'installé sur l'iPhone le 2026-11-12 (spec 001). Ne jamais le modifier :
/// source des étapes légères. `Profile` (spec 002), `Preferences` (spec 003) et le graphe du planning
/// (spec 004) ont changé depuis : leurs formes V1 sont copiées ci-dessous à l'identique ; `WeightEntry`
/// est encore partagé et devra être figé ici de la même manière le jour où il change (pattern Nowtick).
public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            SchemaV1.Profile.self, SchemaV1.Preferences.self, SchemaV1.WeeklyPlan.self, SchemaV1.DayPlan.self,
            SchemaV1.Meal.self, SchemaV1.ExtraEntry.self, SchemaV1.ShoppingItem.self, WeightEntry.self,
        ]
    }

    /// Graphe du planning, forme V1 à V3 (spec 004 ajoute `Meal.time`).
    static var planModels: [any PersistentModel.Type] {
        [
            SchemaV1.WeeklyPlan.self, SchemaV1.DayPlan.self, SchemaV1.Meal.self, SchemaV1.ExtraEntry.self,
            SchemaV1.ShoppingItem.self,
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
        @Relationship(deleteRule: .cascade, inverse: \SchemaV1.DayPlan.plan) public var days: [SchemaV1.DayPlan] = []
        @Relationship(deleteRule: .cascade, inverse: \SchemaV1.ShoppingItem.plan)
        public var shoppingItems: [SchemaV1.ShoppingItem] = []

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
        public var plan: SchemaV1.WeeklyPlan?
        @Relationship(deleteRule: .cascade, inverse: \SchemaV1.Meal.day) public var meals: [SchemaV1.Meal] = []
        @Relationship(deleteRule: .cascade, inverse: \SchemaV1.ExtraEntry.day) public var extras: [SchemaV1.ExtraEntry] = []

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
        public var statusRaw: String
        public var statusChangedAt: Date?
        public var order: Int
        public var day: SchemaV1.DayPlan?

        public init(name: String, order: Int) {
            typeRaw = MealType.lunch.rawValue
            self.name = name
            ingredientsData = Data()
            steps = []
            prepMinutes = 0
            costEUR = 0
            kcal = 0
            proteinG = 0
            carbsG = 0
            fatG = 0
            statusRaw = MealStatus.planned.rawValue
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
        public var day: SchemaV1.DayPlan?

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
        public var plan: SchemaV1.WeeklyPlan?
        public var name: String
        public var key: String
        public var totalQuantity: Double
        public var unitRaw: String
        public var aisleRaw: String
        public var costEUR: Double
        public var isChecked: Bool

        public init(name: String) {
            self.name = name
            key = name
            totalQuantity = 0
            unitRaw = MeasureUnit.g.rawValue
            aisleRaw = Aisle.autre.rawValue
            costEUR = 0
            isChecked = false
        }
    }

    /// Forme V1 (et V2) des préférences.
    @Model
    public final class Preferences {
        public var mealsPerDay: Int
        public var maxPrepMinutes: Int
        public var dailyBudgetEUR: Double
        public var excludedFoods: [String]
        public var likedFoods: [String]
        public var equipment: [String]
        public var batchCooking: Bool
        public var aiModel: String

        public init() {
            mealsPerDay = 4
            maxPrepMinutes = 20
            dailyBudgetEUR = 8
            excludedFoods = []
            likedFoods = []
            equipment = []
            batchCooking = false
            aiModel = "gpt-5-mini"
        }
    }

    @Model
    public final class Profile {
        public var sexRaw: String
        public var birthDate: Date
        public var heightCm: Double
        public var weightKg: Double
        public var activityRaw: String
        public var goalRaw: String
        public var proteinPerKg: Double?
        public var fatPerKg: Double?
        public var calorieAdjustment: Double?
        public var disclaimerAcceptedAt: Date?

        public init(
            sex: Sex, birthDate: Date, heightCm: Double, weightKg: Double, activity: ActivityLevel, goal: Goal
        ) {
            sexRaw = sex.rawValue
            self.birthDate = birthDate
            self.heightCm = heightCm
            self.weightKg = weightKg
            activityRaw = activity.rawValue
            goalRaw = goal.rawValue
        }
    }
}

/// Schéma V2 (spec 002) : `Profile` enrichi de l'activité détaillée et de la calibration.
public enum SchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Profile.self, SchemaV1.Preferences.self, WeightEntry.self] + SchemaV1.planModels
    }
}

/// Schéma V3 (spec 003) : `Preferences` enrichies (budget hebdo, allergies, magasin).
public enum SchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Profile.self, SchemaV3.Preferences.self, WeightEntry.self] + SchemaV1.planModels
    }

    /// Forme V3 des préférences, figée (spec 004 ajoute compléments et heure d'entraînement).
    @Model
    public final class Preferences {
        public var mealsPerDay: Int
        public var maxPrepMinutes: Int
        public var dailyBudgetEUR: Double
        public var excludedFoods: [String]
        public var likedFoods: [String]
        public var equipment: [String]
        public var batchCooking: Bool
        public var aiModel: String
        public var weeklyBudgetEUR: Double?
        public var budgetTolerance: Double?
        public var allergies: [String]?
        public var ingredientAvailabilityRaw: String?
        public var storeRaw: String?
        public var customStoreName: String?

        public init() {
            mealsPerDay = 4
            maxPrepMinutes = 20
            dailyBudgetEUR = 8
            excludedFoods = []
            likedFoods = []
            equipment = []
            batchCooking = false
            aiModel = "gpt-5-mini"
            weeklyBudgetEUR = 56
            budgetTolerance = 0.1
        }
    }
}

/// Schéma V4 (spec 004) : heure des repas, compléments possédés, heure d'entraînement.
public enum SchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Profile.self, Preferences.self, WeeklyPlan.self, DayPlan.self, Meal.self,
            ExtraEntry.self, ShoppingItem.self, WeightEntry.self,
        ]
    }
}

public enum ShreddishMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self] }

    public static var stages: [MigrationStage] {
        // Champs ajoutés tous optionnels : migrations légères, aucune donnée transformée.
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
            .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
        ]
    }
}

public enum ShreddishStore {
    /// Container local, sans CloudKit. `inMemory` : previews et tests ; `url` : tests de migration.
    public static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV4.self)
        let configuration = if let url {
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: ShreddishMigrationPlan.self, configurations: [configuration])
    }
}
