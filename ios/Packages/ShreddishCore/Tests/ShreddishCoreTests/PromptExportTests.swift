import Foundation
import Testing
@testable import ShreddishCore

/// Consignes système copiées dans `backend/prompts/` : le serveur les impose, celles de l'app sont ignorées
/// (spec 023 FR-2311). Entrées types copiées dans `backend/tests/fixtures/inputs/` : le serveur doit les accepter
/// (FR-2312). `SHREDDISH_WRITE_PROMPTS=1 swift test --filter PromptExport` : réécrit les copies.
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

    static let inputs: [String: String] = {
        let preferences = PromptBuilderTests.preferences
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
                feedback: PromptBuilder.budgetRefusalFeedback(reason: "Budget trop serré pour 4 repas protéinés par jour.")
            ),
            "MealReplacementResponse.json": PromptBuilder.replaceMealInput(
                targets: referenceTargets, goal: .cut, preferences: preferences, dayOffset: 2,
                existingDayMeals: dayMeals, mealTypeToReplace: .lunch, avoidMealNames: ["Riz au thon"], costLimitEur: 3
            ),
            "RecipeResponse.json": PromptBuilder.recipeInput(
                meal: dayMeals.first ?? meal(.lunch), supplementDoses: ["Whey : 30 g"], preferences: preferences
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
