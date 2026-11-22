import Foundation
import SwiftData

/// Report des achats d'une semaine à l'autre (spec 017, FR-1706) : les paquets entamés d'articles cochés
/// la semaine précédente (« déjà achetés ») sont déduits des courses suivantes. Produits frais exclus : leur
/// reste est à finir sous 3 jours.
extension PlanStore {
    /// Planning qui précède directement `plan` (fini au plus 7 jours avant son début), actif ou archivé.
    public static func previousPlan(before plan: WeeklyPlan, in context: ModelContext) -> WeeklyPlan? {
        let plans = (try? context.fetch(FetchDescriptor<WeeklyPlan>())) ?? []
        return plans
            .filter { $0.id != plan.id && $0.startDay < plan.startDay && $0.endDay >= plan.startDay.adding(days: -8) }
            .max { ($0.startDay, $0.createdAt) < ($1.startDay, $1.createdAt) }
    }

    /// Restes non périssables des articles cochés du planning précédent, hors ingrédients déjà déclarés à écouler.
    public static func carriedStock(for plan: WeeklyPlan, in context: ModelContext) -> [IngredientDTO] {
        guard let previous = previousPlan(before: plan, in: context) else { return [] }
        let bought = previous.shoppingItems.filter { $0.isChecked && !$0.packing.perishable }
        let declared = Set(plan.pantry.map { TextNormalizer.singular($0.name) })
        return ShoppingListBuilder.leftovers(bought.map(\.line))
            .filter { !declared.contains(TextNormalizer.singular($0.name)) }
    }

    /// Courses du planning suivant recalculées après une coche (reste déjà acheté), coches conservées.
    public static func rebuildFollowingShoppingList(after plan: WeeklyPlan, in context: ModelContext) {
        let next = activePlans(in: context)
            .filter { $0.startDay > plan.startDay && previousPlan(before: $0, in: context)?.id == plan.id }
        for following in next { rebuildShoppingList(for: following, in: context) }
    }
}
