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

    @Test func v2PreferencesMigrateToV3WithDefaults() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "shreddish-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "store.sqlite")

        do {
            let schema = Schema(versionedSchema: SchemaV2.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let preferences = SchemaV1.Preferences()
            preferences.dailyBudgetEUR = 9
            preferences.excludedFoods = ["thon"]
            container.mainContext.insert(preferences)
            try container.mainContext.save()
        }

        let container = try ShreddishStore.makeContainer(url: url)
        let preferences = try #require(try container.mainContext.fetch(FetchDescriptor<Preferences>()).first)
        #expect(preferences.weeklyBudget == 63)
        #expect(preferences.tolerance == 0.1)
        #expect(preferences.excludedFoods == ["thon"])
        #expect(preferences.allergyList.isEmpty)
        #expect(preferences.availability == .everywhere)
        #expect(preferences.store == .generic)
        #expect(preferences.aiModel == "gpt-5-mini")
        PlanStore.cleanUpStoredData(in: container.mainContext)
        #expect(preferences.aiModel == Preferences.defaultAIModel)
    }

    @Test func customModelIsKept() {
        let preferences = Preferences()
        preferences.aiModel = "gpt-5.1"
        #expect(!preferences.upgradeLegacyDefaultModel())
        #expect(preferences.aiModel == "gpt-5.1")
    }

    @Test func v3PlanMigratesToV4WithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "shreddish-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "store.sqlite")

        do {
            let schema = Schema(versionedSchema: SchemaV3.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = container.mainContext
            let preferences = SchemaV3.Preferences()
            preferences.weeklyBudgetEUR = 80
            context.insert(preferences)
            let plan = SchemaV1.WeeklyPlan(startDayKey: 20_261_112, createdAt: .now)
            context.insert(plan)
            let day = SchemaV1.DayPlan(dayKey: 20_261_112, offset: 0)
            plan.days.append(day)
            day.meals.append(SchemaV1.Meal(name: "Poulet riz", order: 0))
            day.extras.append(SchemaV1.ExtraEntry(name: "Carré de chocolat", loggedAt: .now))
            plan.shoppingItems.append(SchemaV1.ShoppingItem(name: "Riz"))
            try context.save()
        }

        let container = try ShreddishStore.makeContainer(url: url)
        let context = container.mainContext
        let meal = try #require(try context.fetch(FetchDescriptor<Meal>()).first)
        #expect(meal.name == "Poulet riz")
        #expect(meal.time == nil)
        #expect(meal.day?.extras.first?.name == "Carré de chocolat")
        #expect(try context.fetchCount(FetchDescriptor<ShoppingItem>()) == 1)
        let preferences = try #require(try context.fetch(FetchDescriptor<Preferences>()).first)
        #expect(preferences.weeklyBudget == 80)
        #expect(preferences.supplementList.isEmpty)
        #expect(preferences.trainingTimeMinutes == nil)
        #expect(preferences.city == nil)
        #expect(preferences.supplementInfoData == nil)
        #expect(preferences.supplementInfo(for: "Whey").isEmpty)
    }

    @Test func deletingPlanRemovesItsDays() throws {
        let (container, context, targets) = try PlanStoreTests.setup()
        _ = container
        let plan = try PlanStore.saveWeek(
            try Fixture.week(), startDay: PlanStoreTests.start, targets: targets, createdAt: .now, in: context
        )
        try PlanStore.deletePlan(plan, in: context)
        #expect(try context.fetchCount(FetchDescriptor<WeeklyPlan>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Meal>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ShoppingItem>()) == 0)
    }
}
