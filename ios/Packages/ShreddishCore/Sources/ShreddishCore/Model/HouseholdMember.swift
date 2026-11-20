import Foundation
import SwiftData

/// Personne du foyer en plus de l'utilisateur (spec 017, FR-1704) : mêmes plats, sa propre portion.
/// Prêt pour CloudKit : valeurs par défaut partout, aucun attribut unique.
@Model
public final class HouseholdMember {
    public static let portionRange = 0.25...2.5

    public var id = UUID()
    public var name = ""
    public var createdAt = Date()
    /// Portion par rapport à celle de l'utilisateur (1 = même assiette). Recalculée depuis le profil si présent.
    public var portion = 1.0
    // Profil facultatif : portion déduite de ses propres besoins.
    public var sexRaw: String?
    public var birthDate: Date?
    public var heightCm: Double?
    public var weightKg: Double?
    public var activityRaw: String?
    public var goalRaw: String?

    public init(name: String, portion: Double = 1, createdAt: Date = .now) {
        self.name = name
        self.portion = Self.clamp(portion)
        self.createdAt = createdAt
    }

    public var hasProfile: Bool { profileInput(on: .now, calendar: .current) != nil }

    /// Entrée du calcul des besoins, nil sans profil complet.
    public func profileInput(on date: Date, calendar: Calendar) -> ProfileInput? {
        guard let sex = sexRaw.flatMap(Sex.init(rawValue:)), let birthDate, let heightCm, let weightKg,
              let activity = activityRaw.flatMap(ActivityLevel.init(rawValue:)),
              let goal = goalRaw.flatMap(Goal.init(rawValue:)) else { return nil }
        let age = calendar.dateComponents([.year], from: birthDate, to: date).year ?? 0
        return ProfileInput(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg, activity: activity, goal: goal)
    }

    public func targets(clock: any AppClock) -> NutritionTargets? {
        profileInput(on: clock.now, calendar: clock.calendar).flatMap { try? NutritionCalculator.targets(for: $0) }
    }

    /// Portion recalculée depuis le profil : ses kcal ÷ celles de l'utilisateur.
    public func refreshPortion(mainKcal: Int, clock: any AppClock) {
        guard mainKcal > 0, let targets = targets(clock: clock) else { return }
        portion = Self.clamp(Double(targets.targetKcal) / Double(mainKcal))
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, portionRange.lowerBound), portionRange.upperBound)
    }
}

/// Foyer : utilisateur + membres.
public enum Household {
    /// Portions totales du foyer (1 = utilisateur seul).
    public static func portions(_ members: [HouseholdMember]) -> Double {
        1 + members.reduce(0) { $0 + $1.portion }
    }

    @MainActor
    public static func portions(in context: ModelContext) -> Double {
        portions((try? context.fetch(FetchDescriptor<HouseholdMember>())) ?? [])
    }

    /// Portions des membres avec profil recalculées (profil de l'utilisateur ou âge changés).
    @MainActor
    public static func refreshPortions(in context: ModelContext, mainKcal: Int, clock: any AppClock) {
        for member in (try? context.fetch(FetchDescriptor<HouseholdMember>())) ?? [] {
            member.refreshPortion(mainKcal: mainKcal, clock: clock)
        }
    }

    /// Ingrédients d'une portion multipliés pour tout le foyer (quantités et coûts).
    public static func scaled(_ ingredients: [IngredientDTO], portions: Double) -> [IngredientDTO] {
        guard portions != 1 else { return ingredients }
        return ingredients.map { ingredient in
            var scaled = ingredient
            scaled.quantity = ingredient.quantity * portions
            scaled.costEur = ingredient.costEur * portions
            return scaled
        }
    }
}
