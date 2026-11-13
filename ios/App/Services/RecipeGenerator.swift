import Foundation
import Observation
import ShreddishCore
import SwiftData

/// Recettes rédigées après la semaine, en arrière-plan (spec 010). Un repas ouvert avant sa recette passe
/// en priorité. Échec : recette laissée vide, redemandée à l'ouverture du repas ou au prochain lancement.
@MainActor
@Observable
final class RecipeGenerator {
    static let maxConcurrent = 4

    private let client: OpenAIClient
    private let keyStore: any APIKeyStore
    /// Repas en cours de rédaction.
    private(set) var inFlight: Set<PersistentIdentifier> = []
    private var queue: [PersistentIdentifier] = []

    init(client: OpenAIClient, keyStore: any APIKeyStore) {
        self.client = client
        self.keyStore = keyStore
    }

    func isPreparing(_ meal: Meal) -> Bool {
        inFlight.contains(meal.persistentModelID) || queue.contains(meal.persistentModelID)
    }

    /// Met en file toutes les recettes manquantes des plannings actifs.
    func fillMissing(in context: ModelContext) {
        let meals = PlanStore.activePlans(in: context).flatMap(\.sortedDays).flatMap(\.sortedMeals).filter(\.needsRecipe)
        for meal in meals where !isPreparing(meal) { queue.append(meal.persistentModelID) }
        pump(context)
    }

    /// Repas ouvert : rédigé tout de suite, hors file.
    func prioritize(_ meal: Meal, in context: ModelContext) {
        guard meal.needsRecipe, !inFlight.contains(meal.persistentModelID) else { return }
        queue.removeAll { $0 == meal.persistentModelID }
        start(meal.persistentModelID, in: context)
    }

    /// Attend la fin de la file (tests).
    func waitUntilIdle() async {
        while !inFlight.isEmpty || !queue.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
    }

    private func pump(_ context: ModelContext) {
        while inFlight.count < Self.maxConcurrent, !queue.isEmpty {
            start(queue.removeFirst(), in: context)
        }
    }

    private func start(_ id: PersistentIdentifier, in context: ModelContext) {
        guard let meal = context.model(for: id) as? Meal, meal.needsRecipe,
              let request = request(for: meal, in: context) else { return }
        inFlight.insert(id)
        let client = client
        Task {
            let steps = try? await client.generate(
                kind: .recipe, instructions: PromptBuilder.recipeInstructions(), input: request.input,
                model: request.model, apiKey: request.apiKey
            )
            let parsed = steps.flatMap { try? AIResponseDecoder.decodeRecipe($0) }
            if let parsed, let meal = context.model(for: id) as? Meal, meal.needsRecipe {
                meal.steps = parsed
                try? context.save()
            }
            inFlight.remove(id)
            pump(context)
        }
    }

    private struct Request {
        let input: String
        let model: String
        let apiKey: String
    }

    private func request(for meal: Meal, in context: ModelContext) -> Request? {
        guard let apiKey = keyStore.read(),
              let preferences = (try? context.fetch(FetchDescriptor<Preferences>()))?.first else { return nil }
        let supplements = preferences.ownedSupplementDetails
        var doses: [String] = []
        if let day = meal.day {
            let meals = day.sortedMeals
            if let host = SupplementPlacement.hostIndex(in: meals.map(\.dto), trainingTimeMinutes: preferences.trainingTimeMinutes),
               meals[host].persistentModelID == meal.persistentModelID {
                doses = SupplementPlacement.doses(supplements)
            }
        }
        let model = preferences.aiModel.trimmingCharacters(in: .whitespaces)
        return Request(
            input: PromptBuilder.recipeInput(meal: meal.dto, supplementDoses: doses, preferences: preferences.promptPreferences),
            model: model.isEmpty ? AIConfig.defaultModel : model, apiKey: apiKey
        )
    }
}

/// Correspondances ingrédient → Ciqual gardées dans les réglages de l'app (spec 010). -1 : absent de Ciqual.
final class UserDefaultsFoodMatchCache: FoodMatchCache, @unchecked Sendable {
    static let key = "foodMatches"
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func code(for key: String) -> Int?? {
        lock.withLock {
            guard let value = (defaults.dictionary(forKey: Self.key) as? [String: Int])?[key] else { return nil }
            return .some(value < 0 ? nil : value)
        }
    }

    func store(_ code: Int?, for key: String) {
        lock.withLock {
            var entries = defaults.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
            entries[key] = code ?? -1
            defaults.set(entries, forKey: Self.key)
        }
    }

    func removeAll() {
        defaults.removeObject(forKey: Self.key)
    }
}
