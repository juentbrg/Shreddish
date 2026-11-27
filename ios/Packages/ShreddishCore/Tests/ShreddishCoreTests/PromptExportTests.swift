import Foundation
import Testing
@testable import ShreddishCore

/// Consignes système copiées dans `backend/prompts/` : le serveur les impose, celles de l'app sont ignorées
/// (spec 023 FR-2311). Entrées types copiées dans `backend/tests/fixtures/inputs/` : le serveur doit les accepter
/// (FR-2312). Clés admises par tâche copiées dans `backend/prompts/input_keys.json` : toute autre clé est refusée.
/// Entrées types maximales (tout champ optionnel rempli, vérifié par `samplesFillEveryOptionalField`) : une
/// clé ajoutée à `PromptBuilder` fait échouer ce test tant que les copies ne sont pas réécrites.
/// `SHREDDISH_WRITE_PROMPTS=1 swift test --filter PromptExport` : réécrit les copies.
struct PromptExportTests {
    static let directory = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "backend/prompts")

    static let prompts = [
        "system.txt": PromptBuilder.systemInstructions(),
        "recipe.txt": PromptBuilder.recipeInstructions(),
        "food_match.txt": PromptBuilder.foodMatchInstructions(),
    ]

    static let supplements: [OwnedSupplement] = [
        #"{"name":"Whey","kind":"macro","serving_g":30,"kcal_per_serving":120,"protein_g_per_serving":24,"#
            + #""carbs_g_per_serving":3,"fat_g_per_serving":1.5,"flavor":"chocolat"}"#,
        #"{"name":"Créatine","kind":"dose","dose":"5 g","doses_per_day":1}"#,
    ].compactMap { try? AIResponseDecoder.decoder.decode(OwnedSupplement.self, from: Data($0.utf8)) }

    /// Préférences dont chaque champ optionnel est rempli.
    static let preferences: PromptPreferences = {
        var preferences = PromptBuilderTests.preferences
        preferences.batchCooking = true
        preferences.ownedSupplements = supplements
        preferences.trainingTime = "18:00"
        preferences.trainingSessionsPerWeek = 4
        preferences.eatingWindow = "12:00-20:00"
        preferences.diets = [Diet.allCases[0]]
        preferences.language = "fr"
        return preferences
    }()

    static let inputs: [String: String] = {
        let preferences = Self.preferences
        let week = (try? Fixture.week()) ?? WeekPlanDTO(prepSessions: [], days: [])
        let dayMeals = week.days.first?.meals ?? []
        let feedback = PromptBuilder.overBudgetFeedback(
            costEur: 71.4, ceilingEur: 61.6,
            expensive: Array(week.days.flatMap(\.meals).flatMap(\.ingredients).sorted { $0.costEur > $1.costEur }.prefix(3))
        )
        return [
            "WeekPlanResponse.json": PromptBuilder.weekInput(
                targets: referenceTargets, goal: .cut, preferences: preferences, feedback: feedback,
                pantry: dayMeals.first?.ingredients ?? [], recipes: Array(dayMeals.prefix(2))
            ),
            "DayPlanResponse.json": PromptBuilder.dayInput(
                targets: referenceTargets, goal: .cut, preferences: preferences, dayOffset: 2,
                avoidMealNames: week.days.flatMap(\.meals).map(\.name), costLimitEur: 9,
                feedback: PromptBuilder.budgetRefusalFeedback(reason: "Budget trop serré pour 4 repas protéinés par jour."),
                pantry: dayMeals.first?.ingredients ?? [], recipes: Array(dayMeals.prefix(1))
            ),
            "MealReplacementResponse.json": PromptBuilder.replaceMealInput(
                targets: referenceTargets, goal: .cut, preferences: preferences, dayOffset: 2,
                existingDayMeals: dayMeals, mealTypeToReplace: .lunch, avoidMealNames: ["Riz au thon"], costLimitEur: 3,
                feedback: feedback
            ),
            "RecipeResponse.json": PromptBuilder.recipeInput(
                meal: meal(.snack, name: "Shaker banane", ingredients: [ingredient("Whey", 30), ingredient("Banane", 1, "piece")], time: "16:00"),
                supplementDoses: ["Créatine : 5 g"], preferences: preferences
            ),
            "FoodMatchResponse.json": PromptBuilder.foodMatchInput([
                FoodQuestion(index: 0, name: "Riz basmati", candidates: [.init(code: 9100, name: "Riz basmati, cru")]),
            ]),
        ]
    }()

    static let inputsDirectory = directory.deletingLastPathComponent().appending(path: "tests/fixtures/inputs")

    @Test func backendInputFixturesMatchTheApp() throws {
        if ProcessInfo.processInfo.environment["SHREDDISH_WRITE_PROMPTS"] == "1" {
            try FileManager.default.createDirectory(at: Self.inputsDirectory, withIntermediateDirectories: true)
            for (name, text) in Self.inputs {
                try text.write(to: Self.inputsDirectory.appending(path: name), atomically: true, encoding: .utf8)
            }
        }
        for (name, text) in Self.inputs {
            let copy = try String(contentsOf: Self.inputsDirectory.appending(path: name), encoding: .utf8)
            #expect(copy == text, "backend/tests/fixtures/inputs/\(name) périmé")
        }
    }

    /// Clés admises par tâche (FR-2312), tirées des entrées types maximales.
    static var inputKeys: Data {
        var keys: [String: Set<String>] = [:]
        for text in inputs.values {
            let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
            keys[object["task"] as? String ?? "?", default: []].formUnion(PromptBuilderTests.allKeys(object))
        }
        let sorted = keys.mapValues { $0.sorted() }
        return (try? JSONSerialization.data(withJSONObject: sorted, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    @Test func backendInputKeysMatchTheApp() throws {
        let file = Self.directory.appending(path: "input_keys.json")
        if ProcessInfo.processInfo.environment["SHREDDISH_WRITE_PROMPTS"] == "1" {
            try Self.inputKeys.write(to: file)
        }
        #expect(try Data(contentsOf: file) == Self.inputKeys, "backend/prompts/input_keys.json périmé")
    }

    /// Entrées types maximales : chaque champ optionnel des préférences et des compléments rempli au moins une fois.
    @Test func samplesFillEveryOptionalField() {
        func emptyFields(_ values: [Any]) -> Set<String> {
            var labels = Set<String>()
            var filled = Set<String>()
            for value in values {
                for child in Mirror(reflecting: value).children {
                    guard let label = child.label else { continue }
                    labels.insert(label)
                    let inner = Mirror(reflecting: child.value)
                    let isNil = inner.displayStyle == .optional && inner.children.isEmpty
                    let isEmpty = (child.value as? [Any])?.isEmpty ?? false
                    if !isNil, !isEmpty { filled.insert(label) }
                }
            }
            return labels.subtracting(filled)
        }
        #expect(emptyFields([Self.preferences]).isEmpty, "\(emptyFields([Self.preferences]))")
        #expect(Self.supplements.count == 2)
        #expect(emptyFields(Self.supplements).isEmpty, "\(emptyFields(Self.supplements))")
    }

    @Test func backendPromptsMatchTheApp() throws {
        if ProcessInfo.processInfo.environment["SHREDDISH_WRITE_PROMPTS"] == "1" {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            for (name, text) in Self.prompts {
                try text.write(to: Self.directory.appending(path: name), atomically: true, encoding: .utf8)
            }
        }
        for (name, text) in Self.prompts {
            let copy = try String(contentsOf: Self.directory.appending(path: name), encoding: .utf8)
            #expect(copy == text, "backend/prompts/\(name) périmé : SHREDDISH_WRITE_PROMPTS=1 swift test --filter PromptExport")
        }
    }
}
