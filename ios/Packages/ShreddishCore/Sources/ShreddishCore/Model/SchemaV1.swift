import Foundation
import SwiftData

/// Schéma V1, figé tel qu'installé sur l'iPhone le 2026-11-12 (spec 001). Ne jamais le modifier :
/// source de l'étape légère vers `SchemaV2`. Seul `Profile` a changé depuis : sa forme V1 est copiée
/// ci-dessous à l'identique ; les autres modèles sont encore partagés avec V2 et devront être figés
/// ici de la même manière le jour où ils changent (pattern Nowtick).
public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            SchemaV1.Profile.self, Preferences.self, WeeklyPlan.self, DayPlan.self, Meal.self,
            ExtraEntry.self, ShoppingItem.self, WeightEntry.self,
        ]
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
        [
            Profile.self, Preferences.self, WeeklyPlan.self, DayPlan.self, Meal.self,
            ExtraEntry.self, ShoppingItem.self, WeightEntry.self,
        ]
    }
}

public enum ShreddishMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }

    public static var stages: [MigrationStage] {
        // Champs ajoutés tous optionnels : migration légère, aucune donnée transformée.
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}

public enum ShreddishStore {
    /// Container local, sans CloudKit. `inMemory` : previews et tests ; `url` : tests de migration.
    public static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration = if let url {
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: ShreddishMigrationPlan.self, configurations: [configuration])
    }
}
