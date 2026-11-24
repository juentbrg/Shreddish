import Foundation
import SwiftData

/// Courses d'un planning validées (spec 019) : avant, la liste suit les repas restants (repas mangés ou sautés
/// retirés) ; après, elle est figée telle qu'achetée. Prêt pour CloudKit : valeurs par défaut, aucun attribut unique.
@Model
public final class ShoppingValidation {
    public var id = UUID()
    /// `WeeklyPlan.id` du planning concerné.
    public var planID = UUID()
    public var validatedAt = Date()

    public init(planID: UUID, validatedAt: Date) {
        self.planID = planID
        self.validatedAt = validatedAt
    }

    public static func find(planID: UUID, in context: ModelContext) -> ShoppingValidation? {
        let descriptor = FetchDescriptor<ShoppingValidation>(predicate: #Predicate { $0.planID == planID })
        return (try? context.fetch(descriptor))?.first
    }

    /// Valide les courses : la liste ne bouge plus.
    @MainActor
    public static func validate(_ plan: WeeklyPlan, at date: Date, in context: ModelContext) {
        guard find(planID: plan.id, in: context) == nil else { return }
        context.insert(ShoppingValidation(planID: plan.id, validatedAt: date))
        try? context.save()
    }

    /// Rouvre la liste : de nouveau recalculée d'après les repas restants.
    @MainActor
    public static func reopen(_ plan: WeeklyPlan, in context: ModelContext) {
        let planID = plan.id
        try? context.delete(model: ShoppingValidation.self, where: #Predicate { $0.planID == planID })
        PlanStore.rebuildShoppingList(for: plan, in: context)
        try? context.save()
    }
}
