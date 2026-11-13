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

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { count += 1 }
        return try await base.send(request)
    }
}

/// Génération réelle avec la clé du build (spec 009). Désactivée par défaut : appels facturés.
/// Lancer avec `TEST_RUNNER_SHREDDISH_LIVE=1 xcodebuild test ... -only-testing:AppTests/LiveGenerationTests`.
/// `TEST_RUNNER_SHREDDISH_LIVE_REPORT=/chemin/rapport.json` écrit la semaine générée et ses mesures.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SHREDDISH_LIVE"] == "1" && BundledKeyStore().read() != nil))
struct LiveGenerationTests {
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
        preferences.storeRaw = GroceryStore.lidl.rawValue
        preferences.city = "Toulouse"
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
