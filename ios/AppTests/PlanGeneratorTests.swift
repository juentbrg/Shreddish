import Foundation
import ShreddishCore
import SwiftData
import Testing
@testable import Shreddish

/// Transport scripté : réponses jouées dans l'ordre, requêtes enregistrées.
final class ScriptedTransport: AITransport, @unchecked Sendable {
    enum Step {
        case output(String)
        case status(Int)
        case failure(URLError.Code)
    }

    private let lock = NSLock()
    private var steps: [Step]
    private(set) var requests: [URLRequest] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    var requestCount: Int { lock.withLock { requests.count } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let step: Step = lock.withLock {
            requests.append(request)
            return steps.isEmpty ? .status(500) : steps.removeFirst()
        }
        let url = request.url ?? AIConfig.baseURL
        switch step {
        case let .output(text):
            let envelope: [String: Any] = [
                "status": "completed",
                "output": [["type": "message", "content": [["type": "output_text", "text": text]]]],
            ]
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (try JSONSerialization.data(withJSONObject: envelope), response)
        case let .status(code):
            return (Data("{}".utf8), HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!)
        case let .failure(code):
            throw URLError(code)
        }
    }
}

@MainActor
struct PlanGeneratorTests {
    let container: ModelContainer
    let context: ModelContext
    let profile: Profile
    let preferences: Preferences
    let clock = FixedClock(day: LocalDay(year: 2026, month: 11, day: 11), hour: 9)

    init() throws {
        container = try ShreddishStore.makeContainer(inMemory: true)
        context = container.mainContext
        let birth = clock.calendar.date(byAdding: .year, value: -30, to: clock.now)!
        profile = Profile(sex: .male, birthDate: birth, heightCm: 180, weightKg: 80, activity: .moderate, goal: .cut)
        preferences = Preferences()
        context.insert(profile)
        context.insert(preferences)
    }

    /// Réponse valide construite comme le stub UI tests, pour la cible du profil.
    func weekText() throws -> String {
        let targets = try #require(profile.targets(clock: clock))
        return try UITestAITransport.response(for: [
            "task": "week",
            "targets": ["kcal": targets.targetKcal, "protein_g": targets.proteinG, "carbs_g": targets.carbsG, "fat_g": targets.fatG],
            "preferences": ["meals_per_day": 4],
        ])
    }

    func dayText(_ offset: Int) throws -> String {
        let targets = try #require(profile.targets(clock: clock))
        return try UITestAITransport.response(for: [
            "task": "day", "day_offset": offset,
            "targets": ["kcal": targets.targetKcal, "protein_g": targets.proteinG, "carbs_g": targets.carbsG, "fat_g": targets.fatG],
            "preferences": ["meals_per_day": 4],
        ])
    }

    func generator(_ transport: ScriptedTransport, key: String? = "sk-test") -> PlanGenerator {
        PlanGenerator(client: OpenAIClient(transport: transport), keyStore: InMemoryKeyStore(key: key), clock: clock)
    }

    @Test func weekIsSavedFromToday() async throws {
        let transport = ScriptedTransport([.output(try weekText())])
        try await generator(transport).generateWeek(profile: profile, preferences: preferences, in: context)
        let plan = try #require(PlanStore.currentPlan(in: context))
        #expect(plan.startDay == clock.today)
        #expect(plan.sortedDays.count == 7)
        #expect(plan.sortedDays.allSatisfy { $0.meals.count == 4 })
        #expect(!plan.shoppingItems.isEmpty)
        #expect(transport.requestCount == 1)
    }

    @Test func requestCarriesKeyAndStrictSchema() async throws {
        let transport = ScriptedTransport([.output(try weekText())])
        try await generator(transport).generateWeek(profile: profile, preferences: preferences, in: context)
        let request = try #require(transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let format = try #require((body["text"] as? [String: Any])?["format"] as? [String: Any])
        #expect(format["strict"] as? Bool == true)
        #expect(format["name"] as? String == "WeekPlanResponse")
        #expect(body["store"] as? Bool == false)
        let input = try #require(body["input"] as? String)
        #expect(!input.contains("weight"))
        #expect(!input.contains("\"age\""))
    }

    @Test func invalidOutputIsRetriedOnce() async throws {
        let transport = ScriptedTransport([.output("{\"pas\":\"valide\"}"), .output(try weekText())])
        try await generator(transport).generateWeek(profile: profile, preferences: preferences, in: context)
        #expect(transport.requestCount == 2)
        #expect(PlanStore.currentPlan(in: context) != nil)
    }

    @Test func timeoutFallsBackToSevenDayRequests() async throws {
        let days = try (0...6).map { Step.output(try dayText($0)) }
        // Les requêtes jour partent en parallèle : toutes reçoivent une réponse jour valide quel que soit
        // l'ordre ; on vérifie seulement la reconstitution des 7 jours.
        let transport = ScriptedTransport([.failure(.timedOut), .failure(.timedOut)] + days)
        try await generator(transport).generateWeek(profile: profile, preferences: preferences, in: context)
        let plan = try #require(PlanStore.currentPlan(in: context))
        #expect(plan.sortedDays.count == 7)
        #expect(transport.requestCount == 9)
    }

    /// Spec 008 : semaine refusée (réponse jugée trop longue) → repli jour par jour.
    @Test func weekRefusalFallsBackToSevenDayRequests() async throws {
        let refusal = #"{"infeasible":"Format de réponse trop long pour 7 jours.","prep_sessions":[],"days":[]}"#
        let days = try (0...6).map { Step.output(try dayText($0)) }
        let transport = ScriptedTransport([.output(refusal)] + days)
        try await generator(transport).generateWeek(profile: profile, preferences: preferences, in: context)
        let plan = try #require(PlanStore.currentPlan(in: context))
        #expect(plan.sortedDays.count == 7)
        #expect(transport.requestCount == 8)
    }

    typealias Step = ScriptedTransport.Step

    /// Spec 010 : semaine sans étapes, recettes rédigées ensuite ; créatine dans le repas d'après séance.
    @Test func recipesAreWrittenAfterTheWeekWithDoses() async throws {
        preferences.supplementList = ["Créatine"]
        preferences.setSupplementInfo(SupplementInfo(doseAmount: 5, doseUnit: .g, dosesPerDay: 1), for: "Créatine")
        preferences.trainingTimeMinutes = 16 * 60
        let recipe = Step.output(#"{"steps":["Étape 1.","Étape 2.","Étape 3.","Étape 4."]}"#)
        let transport = ScriptedTransport([.output(try weekText())] + Array(repeating: recipe, count: 28))
        try await generator(transport).generateWeek(profile: profile, preferences: preferences, in: context)
        let plan = try #require(PlanStore.currentPlan(in: context))
        #expect(plan.sortedDays.flatMap(\.meals).allSatisfy { $0.needsRecipe })

        let recipes = RecipeGenerator(client: OpenAIClient(transport: transport), keyStore: InMemoryKeyStore(key: "sk-test"))
        recipes.fillMissing(in: context)
        await recipes.waitUntilIdle()
        #expect(plan.sortedDays.flatMap(\.meals).allSatisfy { $0.steps.count == 4 })
        #expect(transport.requestCount == 29)
        let inputs = transport.requests.dropFirst().compactMap { request -> String? in
            guard let body = request.httpBody,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
            return json["input"] as? String
        }
        // Une prise par jour, sur la collation de 17 h (premier repas après 16 h).
        #expect(inputs.filter { $0.contains("Créatine : 5 g") }.count == 7)
        #expect(inputs.filter { $0.contains("Créatine : 5 g") }.allSatisfy { $0.contains("\"type\":\"snack\"") })
    }

    @Test func weekAboveBudgetCeilingIsRegenerated() async throws {
        // Viande et poisson à 30 €/kg : plus de 100 € pour un plafond de 56 € × 1,10 = 61,60 € : nouvel essai.
        let expensive = try weekText().replacingOccurrences(of: "\"unit_price_eur\":7}", with: "\"unit_price_eur\":30}")
            .replacingOccurrences(of: "\"unit_price_eur\":9}", with: "\"unit_price_eur\":30}")
        let transport = ScriptedTransport([.output(expensive), .output(try weekText())])
        try await generator(transport).generateWeek(profile: profile, preferences: preferences, in: context)
        #expect(transport.requestCount == 2)
        let plan = try #require(PlanStore.currentPlan(in: context))
        #expect(plan.sortedDays.reduce(0) { $0 + $1.plannedCostEUR } <= preferences.budgetCeiling)
        // Le second essai reçoit le coût obtenu (spec 004).
        let body = try #require(try JSONSerialization.jsonObject(with: transport.requests[1].httpBody ?? Data()) as? [String: Any])
        let input = try #require(body["input"] as? String)
        #expect(input.contains("previous_attempt_feedback"))
        #expect(input.contains("plafond de 61.6"))
    }

    @Test func weekStillAboveCeilingIsKeptWithWarning() async throws {
        // Spec 004 : deux essais au-dessus du plafond → le moins cher est gardé et signalé, pas d'échec.
        let expensive = try weekText().replacingOccurrences(of: "\"unit_price_eur\":7}", with: "\"unit_price_eur\":30}")
            .replacingOccurrences(of: "\"unit_price_eur\":9}", with: "\"unit_price_eur\":30}")
        let lessExpensive = try weekText().replacingOccurrences(of: "\"unit_price_eur\":7}", with: "\"unit_price_eur\":20}")
            .replacingOccurrences(of: "\"unit_price_eur\":9}", with: "\"unit_price_eur\":20}")
        let transport = ScriptedTransport([.output(expensive), .output(lessExpensive)])
        let warnings = try await generator(transport).generateWeek(profile: profile, preferences: preferences, in: context)
        #expect(transport.requestCount == 2)
        #expect(warnings.contains { if case .weekOverBudget = $0 { true } else { false } })
        let plan = try #require(PlanStore.currentPlan(in: context))
        #expect(plan.sortedDays.reduce(0) { $0 + $1.plannedCostEUR } < 100)
    }

    @Test func upcomingWeekStartsOnChosenDayAndKeepsCurrentWeek() async throws {
        // Spec 006 : semaine en cours puis semaine à venir dans 3 jours.
        let transport = ScriptedTransport([.output(try weekText()), .output(try weekText())])
        let generator = generator(transport)
        try await generator.generateWeek(profile: profile, preferences: preferences, in: context)
        let start = clock.today.adding(days: 3)
        try await generator.generateWeek(profile: profile, preferences: preferences, startDay: start, in: context)
        let active = PlanStore.activePlans(in: context)
        #expect(active.count == 2)
        #expect(active.map(\.startDay) == [clock.today, start])
        #expect(active[0].days.count == 3)
    }

    @Test func ownedSupplementsAndTrainingReachThePrompt() async throws {
        preferences.supplementList = ["Whey"]
        preferences.trainingTimeMinutes = 18 * 60 + 30
        let transport = ScriptedTransport([.output(try weekText())])
        try await generator(transport).generateWeek(profile: profile, preferences: preferences, in: context)
        let body = try #require(try JSONSerialization.jsonObject(with: transport.requests[0].httpBody ?? Data()) as? [String: Any])
        let input = try #require(body["input"] as? String)
        #expect(input.contains("\"owned_supplements\":[{\"kind\":\"macro\",\"name\":\"Whey\"}]"))
        #expect(input.contains("\"training_time\":\"18:30\""))
        #expect(input.contains("\"location\":\"France\""))
    }

    @Test func storeAndAllergiesReachThePrompt() async throws {
        preferences.store = .lidl
        preferences.allergyList = ["arachide"]
        let transport = ScriptedTransport([.output(try weekText())])
        try await generator(transport).generateWeek(profile: profile, preferences: preferences, in: context)
        let body = try #require(try JSONSerialization.jsonObject(with: transport.requests[0].httpBody ?? Data()) as? [String: Any])
        let input = try #require(body["input"] as? String)
        #expect(input.contains("\"store\":\"Lidl\""))
        #expect(input.contains("arachide"))
        #expect(input.contains("\"weekly_budget_eur\":56"))
    }

    @Test func missingKeyThrowsWithoutNetwork() async throws {
        let transport = ScriptedTransport([])
        await #expect(throws: AIError.missingKey) {
            try await generator(transport, key: nil).generateWeek(profile: profile, preferences: preferences, in: context)
        }
        #expect(transport.requestCount == 0)
    }

    @Test func invalidKeyIsNotRetried() async throws {
        let transport = ScriptedTransport([.status(401)])
        await #expect(throws: AIError.invalidKey) {
            try await generator(transport).generateWeek(profile: profile, preferences: preferences, in: context)
        }
        #expect(transport.requestCount == 1)
    }

    @Test func offlineKeepsExistingPlan() async throws {
        try await generator(ScriptedTransport([.output(try weekText())]))
            .generateWeek(profile: profile, preferences: preferences, in: context)
        let existing = try #require(PlanStore.currentPlan(in: context))
        await #expect(throws: AIError.offline) {
            try await generator(ScriptedTransport([.failure(.notConnectedToInternet)]))
                .generateWeek(profile: profile, preferences: preferences, in: context)
        }
        #expect(PlanStore.currentPlan(in: context)?.id == existing.id)
    }

    @Test func infeasibleReasonIsSurfaced() async throws {
        let reason = "Allergies et temps de préparation incompatibles."
        let text = #"{"infeasible":"\#(reason)","prep_sessions":[],"days":[]}"#
        let dayRefusal = Step.output(#"{"infeasible":"\#(reason)","day":null}"#)
        await #expect(throws: AIError.infeasible(reason)) {
            try await generator(ScriptedTransport([.output(text)] + Array(repeating: dayRefusal, count: 7)))
                .generateWeek(profile: profile, preferences: preferences, in: context)
        }
    }

    /// Spec 008 : un refus pour budget n'est jamais bloquant.
    @Test func budgetRefusalIsRetriedWithFeedback() async throws {
        let refusal = #"{"infeasible":"Budget de 60 € insuffisant.","prep_sessions":[],"days":[]}"#
        let transport = ScriptedTransport([.output(refusal), .output(try weekText())])
        try await generator(transport).generateWeek(profile: profile, preferences: preferences, in: context)
        #expect(PlanStore.currentPlan(in: context) != nil)
        #expect(transport.requestCount == 2)
        let body = String(bytes: transport.requests[1].httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("jamais un motif de refus"))
    }

    @Test func repeatedBudgetRefusalAnnouncesLargerBudget() async throws {
        let refusal = #"{"infeasible":"Prix trop élevés pour ce budget.","prep_sessions":[],"days":[]}"#
        let transport = ScriptedTransport([.output(refusal), .output(refusal), .output(try weekText())])
        try await generator(transport).generateWeek(profile: profile, preferences: preferences, in: context)
        #expect(PlanStore.currentPlan(in: context) != nil)
        #expect(transport.requestCount == 3)
        let body = String(bytes: transport.requests[2].httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains(#"weekly_budget_eur\":112"#))
    }

    @Test func replaceMealChangesOnlyThatMeal() async throws {
        try await generator(ScriptedTransport([.output(try weekText())]))
            .generateWeek(profile: profile, preferences: preferences, in: context)
        let plan = try #require(PlanStore.currentPlan(in: context))
        let day = plan.sortedDays[2]
        let before = day.sortedMeals.map(\.name)
        let lunch = try #require(day.sortedMeals.first { $0.type == .lunch })
        let targets = try #require(profile.targets(clock: clock))
        let mealText = try UITestAITransport.response(for: [
            "task": "replace_meal", "meal_type_to_replace": "lunch",
            "targets": ["kcal": targets.targetKcal, "protein_g": targets.proteinG, "carbs_g": targets.carbsG, "fat_g": targets.fatG],
            "preferences": ["meals_per_day": 4],
        ])
        try await generator(ScriptedTransport([.output(mealText)]))
            .replaceMeal(lunch, profile: profile, preferences: preferences, in: context)
        let after = day.sortedMeals.map(\.name)
        #expect(after.count == 4)
        #expect(after[1] != before[1])
        #expect(after[0] == before[0] && after[2] == before[2] && after[3] == before[3])
        #expect(plan.sortedDays[3].sortedMeals.map(\.name).allSatisfy { !$0.contains("remplacé") })
    }
}
