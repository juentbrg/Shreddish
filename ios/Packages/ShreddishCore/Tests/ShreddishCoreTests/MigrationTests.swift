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
        #expect(preferences.storeRaw == nil)
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

    /// Spec 013 : planning V6 (forme installée sur l'iPhone) ouvert en V7, ingrédients à écouler vides.
    @Test func v6PlanMigratesToV7WithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "shreddish-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "store.sqlite")

        do {
            let schema = Schema(versionedSchema: SchemaV6.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = container.mainContext
            let preferences = SchemaV6.Preferences()
            preferences.weeklyBudgetEUR = 60
            context.insert(preferences)
            let plan = SchemaV6.WeeklyPlan(startDayKey: 20_261_114, createdAt: .now)
            context.insert(plan)
            let day = SchemaV6.DayPlan(dayKey: 20_261_114, offset: 0)
            plan.days.append(day)
            let meal = SchemaV6.Meal(order: 0)
            meal.name = "Poulet riz"
            meal.time = "12:30"
            day.meals.append(meal)
            day.extras.append(SchemaV6.ExtraEntry(name: "Pomme", loggedAt: .now))
            plan.shoppingItems.append(SchemaV6.ShoppingItem(name: "Riz", key: "riz blanc|g"))
            try context.save()
        }

        let container = try ShreddishStore.makeContainer(url: url)
        let context = container.mainContext
        let plan = try #require(try context.fetch(FetchDescriptor<WeeklyPlan>()).first)
        #expect(plan.pantryData == nil)
        #expect(plan.pantry.isEmpty)
        let meal = try #require(plan.days.first?.meals.first)
        #expect(meal.name == "Poulet riz")
        #expect(meal.time == "12:30")
        #expect(meal.day?.extras.first?.name == "Pomme")
        #expect(plan.shoppingItems.first?.key == "riz blanc|g")
        #expect(try context.fetch(FetchDescriptor<Preferences>()).first?.weeklyBudget == 60)
    }

    /// Spec 014 : base V7 ouverte en V8, planning intact et aucune recette sauvegardée.
    @Test func v7PlanMigratesToV8WithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "shreddish-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "store.sqlite")
        do {
            let schema = Schema(versionedSchema: SchemaV7.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = container.mainContext
            Self.insertV7Plan(mealName: "Poulet riz", pantry: [ingredient("Riz", 300)], in: context)
        }
        let container = try ShreddishStore.makeContainer(url: url)
        let context = container.mainContext
        let plan = try #require(try context.fetch(FetchDescriptor<WeeklyPlan>()).first)
        #expect(plan.isCurrent)
        #expect(plan.days.first?.meals.first?.name == "Poulet riz")
        #expect(plan.pantry.first?.name == "Riz")
        #expect(!plan.shoppingItems.isEmpty)
        #expect(try context.fetch(FetchDescriptor<SavedRecipe>()).isEmpty)
    }

    @Test func v8PreferencesMigrateToV9WithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "shreddish-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "store.sqlite")
        do {
            let schema = Schema(versionedSchema: SchemaV8.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = container.mainContext
            let preferences = SchemaV6.Preferences()
            preferences.mealsPerDay = 3
            preferences.trainingTimeMinutes = 18 * 60
            preferences.supplementInfoData = Data("{}".utf8)
            context.insert(preferences)
            Self.insertV7Plan(mealName: "Poulet riz", pantry: [], in: context)
            context.insert(SavedRecipe(meal: meal(name: "Chili"), savedAt: .now))
            try context.save()
        }
        let container = try ShreddishStore.makeContainer(url: url)
        let context = container.mainContext
        let preferences = try #require(try context.fetch(FetchDescriptor<Preferences>()).first)
        #expect(preferences.mealsPerDay == 3)
        #expect(preferences.trainingTimeMinutes == 18 * 60)
        #expect(preferences.supplementInfoData != nil)
        #expect(preferences.eatingWindow == nil)
        #expect(try context.fetch(FetchDescriptor<WeeklyPlan>()).first?.days.first?.meals.first?.name == "Poulet riz")
        #expect(try context.fetch(FetchDescriptor<SavedRecipe>()).first?.name == "Chili")
    }

    /// Spec 017 : base V9 ouverte en V10, foyer vide, données intactes.
    @Test func v9StoreMigratesToV10WithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "shreddish-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "store.sqlite")
        do {
            let schema = Schema(versionedSchema: SchemaV9.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = container.mainContext
            let preferences = SchemaV9.Preferences()
            preferences.eatingWindowStartMinutes = EatingWindow.default.startMinutes
            preferences.eatingWindowEndMinutes = EatingWindow.default.endMinutes
            context.insert(preferences)
            Self.insertV7Plan(mealName: "Poulet riz", pantry: [], in: context)
            try context.save()
        }
        let container = try ShreddishStore.makeContainer(url: url)
        let context = container.mainContext
        #expect(try context.fetch(FetchDescriptor<Preferences>()).first?.eatingWindow == EatingWindow.default)
        #expect(try context.fetch(FetchDescriptor<WeeklyPlan>()).first?.days.first?.meals.first?.name == "Poulet riz")
        #expect(try context.fetch(FetchDescriptor<HouseholdMember>()).isEmpty)
    }

    /// Spec 017 : base V10 (foyer) ouverte en V11, régimes vides, membres conservés.
    @Test func v10StoreMigratesToV11WithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "shreddish-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "store.sqlite")
        do {
            let schema = Schema(versionedSchema: SchemaV10.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = container.mainContext
            let preferences = SchemaV9.Preferences()
            preferences.mealsPerDay = 3
            context.insert(preferences)
            context.insert(HouseholdMember(name: "Léa", portion: 0.75))
            Self.insertV7Plan(mealName: "Poulet riz", pantry: [], in: context)
            try context.save()
        }
        let container = try ShreddishStore.makeContainer(url: url)
        let context = container.mainContext
        let preferences = try #require(try context.fetch(FetchDescriptor<Preferences>()).first)
        #expect(preferences.mealsPerDay == 3)
        #expect(preferences.diets.isEmpty)
        #expect(try context.fetch(FetchDescriptor<HouseholdMember>()).first?.portion == 0.75)
        let meal = try #require(try context.fetch(FetchDescriptor<Meal>()).first)
        #expect(meal.name == "Poulet riz")
        #expect(meal.eatenFraction == nil)
        #expect(try context.fetch(FetchDescriptor<QuickFood>()).isEmpty)
    }

    /// Spec 017 : base V11 ouverte en V12, mensurations et photos vides, journal rapide conservé.
    @Test func v11StoreMigratesToV12WithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "shreddish-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "store.sqlite")
        do {
            let schema = Schema(versionedSchema: SchemaV11.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            container.mainContext.insert(QuickFood(name: "Banane", per100g: .zero, grams: 120, usedAt: .now))
            try container.mainContext.save()
        }
        let container = try ShreddishStore.makeContainer(url: url)
        let context = container.mainContext
        #expect(try context.fetch(FetchDescriptor<QuickFood>()).first?.name == "Banane")
        #expect(try context.fetch(FetchDescriptor<BodyMeasurement>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ProgressPhoto>()).isEmpty)
    }

    /// Spec 017 : base V12 ouverte en V13, planning et mensurations conservés, tickets et pesées des membres vides.
    @Test func v12StoreMigratesToV13WithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "shreddish-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "store.sqlite")
        do {
            let schema = Schema(versionedSchema: SchemaV12.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let measurement = BodyMeasurement(day: LocalDay(key: 20_261_120), recordedAt: .now)
            measurement.waistCm = 84
            container.mainContext.insert(measurement)
            container.mainContext.insert(HouseholdMember(name: "Léa", portion: 0.75))
            try container.mainContext.save()
        }
        let container = try ShreddishStore.makeContainer(url: url)
        let context = container.mainContext
        #expect(try context.fetch(FetchDescriptor<BodyMeasurement>()).first?.waistCm == 84)
        #expect(try context.fetch(FetchDescriptor<HouseholdMember>()).first?.portion == 0.75)
        #expect(try context.fetch(FetchDescriptor<ShoppingReceipt>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MemberWeight>()).isEmpty)
    }

    /// Planning à la forme V7 à V10 (figée) : un jour, un repas, une ligne de courses.
    static func insertV7Plan(mealName: String, pantry: [IngredientDTO], in context: ModelContext) {
        let plan = SchemaV7.WeeklyPlan(startDayKey: 20_261_115, createdAt: .now)
        plan.pantryData = pantry.isEmpty ? nil : try? JSONEncoder().encode(pantry)
        context.insert(plan)
        let day = SchemaV7.DayPlan(dayKey: 20_261_115, offset: 0)
        plan.days.append(day)
        let meal = SchemaV7.Meal(order: 0)
        meal.name = mealName
        meal.ingredientsData = (try? JSONEncoder().encode([ingredient("Riz", 80)])) ?? Data()
        day.meals.append(meal)
        plan.shoppingItems.append(SchemaV7.ShoppingItem(name: "Riz", key: "riz|g"))
        try? context.save()
    }

    /// Copie de la vraie base de l'iPhone (`tools/backup/backup.sh`) : `SHREDDISH_REAL_STORE=<dossier>`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SHREDDISH_REAL_STORE"] != nil))
    func realBackupOpensWithCurrentSchema() throws {
        let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SHREDDISH_REAL_STORE"]))
        let directory = FileManager.default.temporaryDirectory.appending(path: "shreddish-real-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in try FileManager.default.contentsOfDirectory(atPath: source.path) {
            try FileManager.default.copyItem(at: source.appending(path: name), to: directory.appending(path: name))
        }
        let container = try ShreddishStore.makeContainer(url: directory.appending(path: "default.store"))
        let context = container.mainContext
        let plans = try context.fetch(FetchDescriptor<WeeklyPlan>())
        let meals = plans.flatMap(\.days).flatMap(\.meals)
        print("REAL plans \(plans.count), repas \(meals.count), courses \(plans.flatMap(\.shoppingItems).count)")
        let hasCurrent = plans.contains { $0.isCurrent }
        #expect(hasCurrent)
        #expect(meals.count >= 28)
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
