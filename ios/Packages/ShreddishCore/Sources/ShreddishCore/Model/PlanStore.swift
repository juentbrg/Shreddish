import Foundation
import SwiftData

/// Écritures du planning : sauvegarde d'une semaine validée, remplacements, liste de courses.
/// Appelé seulement avec des DTO déjà validés (`AIOutputValidator`).
@MainActor
public enum PlanStore {
    public static func currentPlan(in context: ModelContext) -> WeeklyPlan? {
        var descriptor = FetchDescriptor<WeeklyPlan>(
            predicate: #Predicate { $0.isCurrent }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Enregistre une semaine validée comme planning courant ; l'ancien passe en historique.
    /// Une seule sauvegarde à la fin : aucun état partiel si l'app est fermée avant (edge case spec).
    @discardableResult
    public static func saveWeek(
        _ week: WeekPlanDTO, startDay: LocalDay, targets: NutritionTargets, createdAt: Date, in context: ModelContext
    ) throws -> WeeklyPlan {
        let previous = (try? context.fetch(FetchDescriptor<WeeklyPlan>(predicate: #Predicate { $0.isCurrent }))) ?? []
        for plan in previous { plan.isCurrent = false }

        let plan = WeeklyPlan(startDay: startDay, createdAt: createdAt, targets: targets, prepSessions: week.prepSessions)
        context.insert(plan)
        for dayDTO in week.days {
            let day = DayPlan(day: startDay.adding(days: dayDTO.dayOffset), offset: dayDTO.dayOffset)
            plan.days.append(day)
            for (index, mealDTO) in sortedMeals(dayDTO.meals).enumerated() {
                day.meals.append(Meal(dto: mealDTO, order: index))
            }
        }
        rebuildShoppingList(for: plan, in: context)
        try context.save()
        return plan
    }

    /// Remplace les repas d'un jour (régénération) ; extras conservés.
    public static func replaceDay(_ day: DayPlan, with dto: DayPlanDTO, in context: ModelContext) throws {
        for meal in day.meals { context.delete(meal) }
        day.meals = []
        for (index, mealDTO) in sortedMeals(dto.meals).enumerated() {
            day.meals.append(Meal(dto: mealDTO, order: index))
        }
        if let plan = day.plan { rebuildShoppingList(for: plan, in: context) }
        try context.save()
    }

    /// Remplace un repas : nouveau repas au même rang, statut `planned`.
    @discardableResult
    public static func replaceMeal(_ meal: Meal, with dto: MealDTO, in context: ModelContext) throws -> Meal? {
        guard let day = meal.day else { return nil }
        let order = meal.order
        day.meals.removeAll { $0.persistentModelID == meal.persistentModelID }
        context.delete(meal)
        let replacement = Meal(dto: dto, order: order)
        day.meals.append(replacement)
        if let plan = day.plan { rebuildShoppingList(for: plan, in: context) }
        try context.save()
        return replacement
    }

    /// Reconstruit la liste de courses depuis le planning ; coches conservées par clé.
    public static func rebuildShoppingList(for plan: WeeklyPlan, in context: ModelContext) {
        let checked = Set(plan.shoppingItems.filter(\.isChecked).map(\.key))
        for item in plan.shoppingItems { context.delete(item) }
        plan.shoppingItems = []
        let lines = ShoppingListBuilder.build(from: plan.days.flatMap { $0.meals.flatMap(\.ingredients) })
        for line in lines {
            plan.shoppingItems.append(ShoppingItem(line: line, isChecked: checked.contains(line.key)))
        }
    }

    private static func sortedMeals(_ meals: [MealDTO]) -> [MealDTO] {
        meals.enumerated()
            .sorted { ($0.element.type.sortIndex, $0.offset) < ($1.element.type.sortIndex, $1.offset) }
            .map(\.element)
    }
}
