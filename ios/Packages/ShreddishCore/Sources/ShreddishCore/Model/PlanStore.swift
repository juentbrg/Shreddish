import Foundation
import SwiftData

/// Écritures du planning : sauvegarde d'une semaine validée, remplacements, liste de courses.
/// Appelé seulement avec des DTO déjà validés (`AIOutputValidator`).
@MainActor
public enum PlanStore {
    /// Dernier planning actif créé.
    public static func currentPlan(in context: ModelContext) -> WeeklyPlan? {
        activePlans(in: context).max { $0.createdAt < $1.createdAt }
    }

    /// Plannings actifs (en cours ou à venir), triés par date de début (spec 006).
    public static func activePlans(in context: ModelContext) -> [WeeklyPlan] {
        let plans = (try? context.fetch(FetchDescriptor<WeeklyPlan>(predicate: #Predicate { $0.isCurrent }))) ?? []
        return plans.sorted { $0.startDay < $1.startDay }
    }

    /// Semaines parcourables dans l'ordre : historique terminé avant le premier planning actif (le plus récent
    /// gagne en cas de chevauchement), puis plannings actifs.
    public static func browsableWeeks(active: [WeeklyPlan], history: [WeeklyPlan]) -> [WeeklyPlan] {
        let sortedActive = active.sorted { $0.startDay < $1.startDay }
        let firstActive = sortedActive.first?.startDay
        var kept: [WeeklyPlan] = []
        for plan in history.sorted(by: { $0.createdAt > $1.createdAt }) where !plan.days.isEmpty {
            if let firstActive, plan.endDay >= firstActive { continue }
            if kept.contains(where: { $0.startDay <= plan.endDay && plan.startDay <= $0.endDay }) { continue }
            kept.append(plan)
        }
        return kept.sorted { $0.startDay < $1.startDay } + sortedActive
    }

    /// Planning affiché par défaut : celui qui contient `today`, sinon le prochain, sinon le plus récent.
    public static func focusPlan(_ plans: [WeeklyPlan], today: LocalDay) -> WeeklyPlan? {
        let sorted = plans.sorted { $0.startDay < $1.startDay }
        return sorted.first { $0.contains(today) }
            ?? sorted.first { $0.startDay > today }
            ?? sorted.last
    }

    /// Enregistre une période validée de `startDay` (aujourd'hui ou plus tard, spec 006) à son dernier jour généré.
    /// Seuls les jours des plannings actifs compris dans la période sont remplacés ; ceux d'avant et d'après restent.
    /// Planning entièrement couvert → historique, intact. Jour remplacé déjà commencé (aujourd'hui) → historique,
    /// journal conservé ; jours futurs remplacés → supprimés. Une seule sauvegarde à la fin : aucun état partiel.
    @discardableResult
    public static func saveWeek(
        _ week: WeekPlanDTO, startDay: LocalDay, targets: NutritionTargets, createdAt: Date, today: LocalDay? = nil,
        pantry: [IngredientDTO] = [], in context: ModelContext
    ) throws -> WeeklyPlan {
        let today = today ?? startDay
        let endDay = startDay.adding(days: max(week.days.map(\.dayOffset).max() ?? 6, 0))
        for plan in activePlans(in: context) {
            carve(plan, from: startDay, to: endDay, today: today, in: context)
            if plan.isCurrent, plan.endDay < today { plan.isCurrent = false }
        }

        let plan = WeeklyPlan(startDay: startDay, createdAt: createdAt, targets: targets, prepSessions: week.prepSessions)
        plan.pantry = pantry
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

    /// Retire d'un planning actif les jours de `start...end`. Jours d'après la période séparés dans leur propre
    /// planning si des jours la précèdent, sinon le planning repart de son premier jour restant.
    private static func carve(_ plan: WeeklyPlan, from start: LocalDay, to end: LocalDay, today: LocalDay, in context: ModelContext) {
        let covered = plan.days.filter { start <= $0.day && $0.day <= end }
        guard !covered.isEmpty else { return }
        guard covered.count < plan.days.count else {
            plan.isCurrent = false
            return
        }
        let coveredIDs = Set(covered.map(\.persistentModelID))
        plan.days.removeAll { coveredIDs.contains($0.persistentModelID) }
        let started = covered.filter { $0.day <= today }
        if !started.isEmpty {
            let archive = sibling(of: plan, in: context)
            archive.isCurrent = false
            for day in started { archive.days.append(day) }
            rebase(archive)
            rebuildShoppingList(for: archive, in: context)
        }
        for day in covered where day.day > today { context.delete(day) }

        let tail = plan.days.filter { $0.day > end }
        if !tail.isEmpty, plan.days.contains(where: { $0.day < start }) {
            let next = sibling(of: plan, in: context)
            next.pantry = plan.pantry
            let tailIDs = Set(tail.map(\.persistentModelID))
            plan.days.removeAll { tailIDs.contains($0.persistentModelID) }
            for day in tail { next.days.append(day) }
            rebase(next)
            rebuildShoppingList(for: next, in: context)
        } else {
            rebase(plan)
        }
        rebuildShoppingList(for: plan, in: context)
    }

    /// Planning vide aux mêmes cibles, même date de création et mêmes rangs de jours que `plan`.
    private static func sibling(of plan: WeeklyPlan, in context: ModelContext) -> WeeklyPlan {
        let sibling = WeeklyPlan(startDay: plan.startDay, createdAt: plan.createdAt, targetsData: plan.targetsData)
        context.insert(sibling)
        return sibling
    }

    /// Premier jour du planning recalé sur son premier jour restant ; rangs et sessions de batch cooking décalés.
    private static func rebase(_ plan: WeeklyPlan) {
        guard let first = plan.days.map(\.day).min(), first > plan.startDay else { return }
        let shift = first.days(since: plan.startDay)
        plan.startDayKey = first.key
        for day in plan.days { day.offset -= shift }
        plan.prepSessions = plan.prepSessions.compactMap { session in
            var session = session
            session.dayOffset -= shift
            return session.dayOffset >= 0 ? session : nil
        }
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

    /// Repas modifié par l'utilisateur (spec 017) : contenu remplacé, courses recalculées.
    public static func updateMeal(_ meal: Meal, with dto: MealDTO, in context: ModelContext) throws {
        meal.apply(dto)
        if let plan = meal.day?.plan { rebuildShoppingList(for: plan, in: context) }
        try context.save()
    }

    /// Reconstruit la liste de courses depuis le planning ; coches conservées par clé.
    public static func rebuildShoppingList(for plan: WeeklyPlan, in context: ModelContext) {
        let checked = Set(plan.shoppingItems.filter(\.isChecked).map(\.key))
        for item in plan.shoppingItems { context.delete(item) }
        plan.shoppingItems = []
        for line in shoppingLines(for: plan, in: context) {
            plan.shoppingItems.append(ShoppingItem(line: line, isChecked: checked.contains(line.key)))
        }
    }

    static func shoppingLines(for plan: WeeklyPlan, in context: ModelContext) -> [ShoppingLine] {
        let owned = (try? context.fetch(FetchDescriptor<Preferences>()))?.first?.supplementList ?? []
        let ingredients = plan.days.flatMap { $0.meals.flatMap(\.ingredients) }
        return ShoppingListBuilder.build(
            from: Household.scaled(ingredients, portions: Household.portions(in: context)), owned: owned,
            pantry: plan.pantry + carriedStock(for: plan, in: context)
        )
    }

    /// Courses des plannings actifs recalculées (foyer modifié), coches conservées.
    public static func rebuildActiveShoppingLists(in context: ModelContext) {
        for plan in activePlans(in: context) { rebuildShoppingList(for: plan, in: context) }
        try? context.save()
    }

    /// Reconstruit une liste faite par une version antérieure (ex. œufs en double avant la spec 012).
    static func rebuildStaleShoppingList(for plan: WeeklyPlan, in context: ModelContext) {
        let keys = Set(shoppingLines(for: plan, in: context).map(\.key))
        if keys != Set(plan.shoppingItems.map(\.key)) { rebuildShoppingList(for: plan, in: context) }
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
            rebuildStaleShoppingList(for: plan, in: context)
        }
        for item in (try? context.fetch(FetchDescriptor<ShoppingItem>())) ?? [] { item.cleanUp(with: clean) }
        for extra in (try? context.fetch(FetchDescriptor<ExtraEntry>())) ?? [] where clean(extra.name) != extra.name {
            extra.name = clean(extra.name)
        }
        for preferences in (try? context.fetch(FetchDescriptor<Preferences>())) ?? [] {
            preferences.upgradeLegacyDefaultModel()
        }
        if context.hasChanges { try? context.save() }
    }
}
