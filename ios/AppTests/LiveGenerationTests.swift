import Foundation
import ShreddishCore
import SwiftData
import Testing
@testable import Shreddish

/// Transport réel qui compte les appels.
final class CountingTransport: AITransport, @unchecked Sendable {
    private let base = URLSessionTransport()
    private let lock = NSLock()
    private var count = 0

    var requestCount: Int { lock.withLock { count } }

    private(set) var kinds: [String: Int] = [:]
    /// Tokens par type de requête : entrée, entrée en cache, sortie (raisonnement compris).
    private(set) var usage: [String: TokenUsage] = [:]

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let kind = ((body?["text"] as? [String: Any])?["format"] as? [String: Any])?["name"] as? String ?? "?"
        lock.withLock {
            count += 1
            kinds[kind, default: 0] += 1
        }
        let (data, response) = try await base.send(request)
        let tokens = TokenUsage(response: data)
        lock.withLock { usage[kind, default: TokenUsage()].add(tokens) }
        return (data, response)
    }

    var totalUsage: TokenUsage { lock.withLock { usage.values.reduce(into: TokenUsage()) { $0.add($1) } } }
}

/// Tokens facturés d'une ou plusieurs réponses (Responses API, champ `usage`).
struct TokenUsage: Sendable {
    /// gpt-6-luna, $ par million de tokens : entrée, entrée en cache, sortie.
    static let inputPrice = 0.10
    static let cachedPrice = 0.01
    static let outputPrice = 0.50

    var input = 0
    var cached = 0
    var output = 0
    var reasoning = 0

    init() {}

    init(response data: Data) {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let usage = json?["usage"] as? [String: Any]
        input = usage?["input_tokens"] as? Int ?? 0
        cached = (usage?["input_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int ?? 0
        output = usage?["output_tokens"] as? Int ?? 0
        reasoning = (usage?["output_tokens_details"] as? [String: Any])?["reasoning_tokens"] as? Int ?? 0
    }

    mutating func add(_ other: TokenUsage) {
        input += other.input
        cached += other.cached
        output += other.output
        reasoning += other.reasoning
    }

    var costUSD: Double {
        (Double(input - cached) * Self.inputPrice + Double(cached) * Self.cachedPrice + Double(output) * Self.outputPrice)
            / 1_000_000
    }

    var summary: String {
        String(format: "entrée %d (cache %d), sortie %d (raisonnement %d), %.4f $", input, cached, output, reasoning, costUSD)
    }
}

/// Génération réelle avec la clé du build (spec 009). Désactivée par défaut : appels facturés.
/// Lancer avec `TEST_RUNNER_SHREDDISH_LIVE=1 xcodebuild test ... -only-testing:AppTests/LiveGenerationTests`.
/// `TEST_RUNNER_SHREDDISH_LIVE_REPORT=/chemin/rapport.json` écrit la semaine générée et ses mesures.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SHREDDISH_LIVE"] == "1" && BundledKeyStore().read() != nil))
struct LiveGenerationTests {
    static func delta(_ after: TokenUsage, _ before: TokenUsage) -> TokenUsage {
        var result = TokenUsage()
        result.input = after.input - before.input
        result.cached = after.cached - before.cached
        result.output = after.output - before.output
        result.reasoning = after.reasoning - before.reasoning
        return result
    }

    @Test(.timeLimit(.minutes(10)))
    func realWeekMeetsTargets() async throws {
        let container = try ShreddishStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let clock = SystemClock()
        let birth = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
        let profile = Profile(sex: .male, birthDate: birth, heightCm: 180, weightKg: 80, activity: .moderate, goal: .cut)
        let preferences = Preferences()
        preferences.mealsPerDay = 4
        preferences.weeklyBudgetEUR = 60
        preferences.supplementList = ["Whey", "Créatine"]
        preferences.setSupplementInfo(
            SupplementInfo(servingG: 30, kcalPerServing: 118, proteinPerServingG: 24, carbsPerServingG: 2, fatPerServingG: 1.5),
            for: "Whey"
        )
        preferences.setSupplementInfo(SupplementInfo(doseAmount: 5, doseUnit: .g, dosesPerDay: 1), for: "Créatine")
        if let model = ProcessInfo.processInfo.environment["SHREDDISH_LIVE_MODEL"] { preferences.aiModel = model }
        context.insert(profile)
        context.insert(preferences)

        let transport = CountingTransport()
        let generator = PlanGenerator(client: OpenAIClient(transport: transport), keyStore: BundledKeyStore(), clock: clock)
        let started = Date()
        let warnings = try await generator.generateWeek(profile: profile, preferences: preferences, in: context)
        let seconds = Date().timeIntervalSince(started)
        let recipes = RecipeGenerator(client: OpenAIClient(transport: transport), keyStore: BundledKeyStore())
        let recipesStarted = Date()
        recipes.fillMissing(in: context)
        await recipes.waitUntilIdle()
        print("LIVE requêtes par type \(transport.kinds.sorted { $0.key < $1.key })")
        print("LIVE recettes \(Int(Date().timeIntervalSince(recipesStarted))) s")
        let weekUsage = transport.totalUsage
        print("LIVE COUT semaine + recettes : \(weekUsage.summary)")

        // Actions ponctuelles : un repas remplacé, un jour régénéré (recettes comprises).
        let plan0 = try #require(PlanStore.currentPlan(in: context))
        let meal = try #require(plan0.sortedDays.first?.sortedMeals.first { $0.type == .lunch })
        _ = try await generator.replaceMeal(meal, profile: profile, preferences: preferences, in: context)
        recipes.fillMissing(in: context)
        await recipes.waitUntilIdle()
        let afterReplace = transport.totalUsage
        print("LIVE COUT remplacement repas : \(Self.delta(afterReplace, weekUsage).summary)")
        let day = try #require(plan0.sortedDays.last)
        _ = try await generator.regenerateDay(day, profile: profile, preferences: preferences, in: context)
        recipes.fillMissing(in: context)
        await recipes.waitUntilIdle()
        print("LIVE COUT jour régénéré : \(Self.delta(transport.totalUsage, afterReplace).summary)")
        for (kind, tokens) in transport.usage.sorted(by: { $0.key < $1.key }) {
            print("LIVE COUT par type \(kind) : \(tokens.summary)")
        }

        let plan = try #require(PlanStore.currentPlan(in: context))
        let targets = try #require(plan.targets).macros
        #expect(plan.sortedDays.count == 7)
        #expect(plan.sortedDays.allSatisfy { $0.meals.count == 4 })

        let report = LiveReport(
            plan: plan, targets: targets, budget: preferences.weeklyBudget, seconds: seconds,
            requests: transport.requestCount, warnings: warnings.map { String(describing: $0) }
        )
        print(report.summary)
        if let path = ProcessInfo.processInfo.environment["SHREDDISH_LIVE_REPORT"] {
            try report.json().write(to: URL(fileURLWithPath: path))
        }
    }
}

/// Mesures d'une semaine générée.
struct LiveReport {
    let plan: WeeklyPlan
    let targets: MacroTotals
    let budget: Double
    let seconds: Double
    let requests: Int
    let warnings: [String]

    private var meals: [Meal] { plan.sortedDays.flatMap(\.sortedMeals) }

    var summary: String {
        var lines = ["LIVE \(Int(seconds)) s, \(requests) requête(s), batch \(plan.prepSessions.count) session(s)"]
        for day in plan.sortedDays {
            let totals = day.plannedTotals
            lines.append(String(
                format: "LIVE J%d kcal %+.1f%% P %+.1f%% G %+.1f%% L %+.1f%% coût %.2f €",
                day.offset, pct(totals.kcal, targets.kcal), pct(totals.proteinG, targets.proteinG),
                pct(totals.carbsG, targets.carbsG), pct(totals.fatG, targets.fatG), day.plannedCostEUR
            ))
        }
        let cost = plan.sortedDays.reduce(0) { $0 + $1.plannedCostEUR }
        let cooked = meals.filter { $0.type != .snack }
        let steps = cooked.map(\.steps.count)
        let words = meals.flatMap(\.steps).map { $0.split(separator: " ").count }
        lines.append(String(format: "LIVE semaine %.2f € pour %.0f € de budget", cost, budget))
        lines.append("LIVE étapes repas cuisinés min \(steps.min() ?? 0) max \(steps.max() ?? 0), "
            + "mots par étape \(words.isEmpty ? 0 : words.reduce(0, +) / words.count)")
        lines.append("LIVE plats distincts \(Set(meals.map(\.name)).count) / \(meals.count), "
            + "whey \(meals.filter { $0.ingredients.contains { $0.name.localizedCaseInsensitiveContains("whey") } }.count), "
            + "créatine \(meals.filter { $0.steps.contains { $0.localizedCaseInsensitiveContains("créatine") } }.count)")
        let lines011 = meals.flatMap(\.ingredients).filter { ($0.unitPriceEur ?? 0) > 0 }
        let fromTable = lines011.filter { $0.foodCode.flatMap(PriceCatalog.shared.price(code:)) != nil }
        lines.append("LIVE prix table \(fromTable.count) / \(lines011.count) lignes payantes")
        let summary = plan.shoppingSummary
        lines.append(String(
            format: "LIVE ticket %.2f € · gardé %.2f € · perdu %.2f € · semaine %.2f €",
            summary.checkoutEur, summary.keptEur, summary.wastedEur, summary.weekCostEur
        ))
        for item in plan.shoppingItems.sorted(by: { $0.name < $1.name }) {
            let packing = item.packing
            guard packing.perishable, packing.leftover > 0 else { continue }
            lines.append(String(
                format: "LIVE reste périssable %@ : %.0f %@ (%d × %.0f)", item.name, packing.leftover, item.unitRaw,
                packing.packCount, packing.packSize ?? 0
            ))
        }
        lines.append("LIVE avertissements : \(warnings.isEmpty ? "aucun" : warnings.joined(separator: " ; "))")
        return lines.joined(separator: "\n")
    }

    func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(plan.dto)
    }

    private func pct(_ value: Double, _ target: Double) -> Double {
        target > 0 ? (value - target) / target * 100 : 0
    }
}
