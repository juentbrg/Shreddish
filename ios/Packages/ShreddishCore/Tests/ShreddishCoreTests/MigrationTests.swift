import Foundation
import SwiftData
import Testing
@testable import ShreddishCore

@MainActor
struct MigrationTests {
    @Test func v1StoreOpensWithV2WithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "shreddish-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "store.sqlite")

        do {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let profile = SchemaV1.Profile(
                sex: .male, birthDate: Date(timeIntervalSince1970: 0), heightCm: 180, weightKg: 80,
                activity: .moderate, goal: .cut
            )
            profile.disclaimerAcceptedAt = Date(timeIntervalSince1970: 1)
            container.mainContext.insert(profile)
            container.mainContext.insert(WeightEntry(day: LocalDay(year: 2026, month: 11, day: 1), weightKg: 80, recordedAt: .now))
            try container.mainContext.save()
        }

        let container = try ShreddishStore.makeContainer(url: url)
        let profiles = try container.mainContext.fetch(FetchDescriptor<Profile>())
        let profile = try #require(profiles.first)
        #expect(profiles.count == 1)
        #expect(profile.heightCm == 180)
        #expect(profile.activity == .moderate)
        #expect(profile.disclaimerAcceptedAt != nil)
        #expect(profile.dailyActivity == nil)
        #expect(profile.training == nil)
        #expect(profile.tdeeAdjustmentKcal == nil)
        #expect(profile.isAutoCalibrationOn)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<WeightEntry>()) == 1)
    }
}
