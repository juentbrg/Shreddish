import Foundation
import SwiftData

/// Schéma V1 (research R14). À figer une fois livré sur l'iPhone : toute évolution passe par un
/// `SchemaV2` et une étape dans `ShreddishMigrationPlan` (pattern Nowtick).
public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Profile.self, Preferences.self, WeeklyPlan.self, DayPlan.self, Meal.self,
            ExtraEntry.self, ShoppingItem.self, WeightEntry.self,
        ]
    }
}

public enum ShreddishMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

public enum ShreddishStore {
    /// Container local, sans CloudKit. `inMemory` : previews et tests.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: ShreddishMigrationPlan.self, configurations: [configuration])
    }
}
