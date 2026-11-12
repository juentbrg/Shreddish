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
        let owned = (try? context.fetch(FetchDescriptor<Preferences>()))?.first?.supplementList ?? []
        let lines = ShoppingListBuilder.build(from: plan.days.flatMap { $0.meals.flatMap(\.ingredients) }, owned: owned)
        for line in lines {
            plan.shoppingItems.append(ShoppingItem(line: line, isChecked: checked.contains(line.key)))
        }
    }

    /// Supprime un planning et tout ce qui en dépend (jours, repas, extras du journal, courses).
    public static func deletePlan(_ plan: WeeklyPlan, in context: ModelContext) throws {
        context.delete(plan)
        try context.save()
    }

    private static func sortedMeals(_ meals: [MealDTO]) -> [MealDTO] {
        meals.enumerated()
            .sorted { ($0.element.type.sortIndex, $0.offset) < ($1.element.type.sortIndex, $1.offset) }
            .map(\.element)
    }

    /// Nettoyage au lancement : tirets cadratins des textes déjà générés, ancien modèle IA par défaut.
    public static func cleanUpStoredData(in context: ModelContext) {
        let clean = TextNormalizer.withoutDashes
        func cleanData(_ data: Data) -> Data {
            String(data: data, encoding: .utf8).map { Data(clean($0).utf8) } ?? data
        }
        for meal in (try? context.fetch(FetchDescriptor<Meal>())) ?? [] {
            if clean(meal.name) != meal.name { meal.name = clean(meal.name) }
            let steps = meal.steps.map(clean)
            if steps != meal.steps { meal.steps = steps }
            let ingredients = cleanData(meal.ingredientsData)
            if ingredients != meal.ingredientsData { meal.ingredientsData = ingredients }
        }
        for plan in (try? context.fetch(FetchDescriptor<WeeklyPlan>())) ?? [] {
            let sessions = cleanData(plan.prepSessionsData)
            if sessions != plan.prepSessionsData { plan.prepSessionsData = sessions }
        }
        for item in (try? context.fetch(FetchDescriptor<ShoppingItem>())) ?? [] where clean(item.name) != item.name {
            item.name = clean(item.name)
        }
        for extra in (try? context.fetch(FetchDescriptor<ExtraEntry>())) ?? [] where clean(extra.name) != extra.name {
            extra.name = clean(extra.name)
        }
        for preferences in (try? context.fetch(FetchDescriptor<Preferences>())) ?? [] {
            preferences.upgradeLegacyDefaultModel()
        }
        if context.hasChanges { try? context.save() }
    }
}
