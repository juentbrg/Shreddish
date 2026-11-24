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
        // Aujourd'hui remplacé : repas déjà cochés et extras repris dans le nouveau planning (journal visible).
        let startedToday = startDay <= today && today <= endDay
            ? activePlans(in: context).flatMap(\.days).filter { $0.day == today } : []
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
        if let target = plan.days.first(where: { $0.day == today }) {
            for source in startedToday { carryLogged(from: source, to: target, in: context) }
        }
        rebuildShoppingList(for: plan, in: context)
        try context.save()
        return plan
    }

    /// Repas déjà mangés ou sautés et extras de `source` repris dans `target` ; un repas prévu de `target` du même
    /// type qu'un repas repris est supprimé (petit-déjeuner mangé : pas de second petit-déjeuner). Rangs recalculés.
    static func carryLogged(from source: DayPlan, to target: DayPlan, in context: ModelContext) {
        let logged = source.sortedMeals.filter { $0.status != .planned }
        let extras = source.extras
        guard !logged.isEmpty || !extras.isEmpty else { return }
        var types = Dictionary(logged.map { ($0.type, 1) }, uniquingKeysWith: +)
        for meal in target.sortedMeals where meal.status == .planned {
            guard let count = types[meal.type], count > 0 else { continue }
            types[meal.type] = count - 1
            target.meals.removeAll { $0.persistentModelID == meal.persistentModelID }
            context.delete(meal)
        }
        let loggedIDs = Set(logged.map(\.persistentModelID))
        source.meals.removeAll { loggedIDs.contains($0.persistentModelID) }
        source.extras = []
        target.meals.append(contentsOf: logged)
        target.extras.append(contentsOf: extras)
        let ordered = target.meals.sorted {
            ($0.type.sortIndex, $0.status == .planned ? 1 : 0, $0.order) < ($1.type.sortIndex, $1.status == .planned ? 1 : 0, $1.order)
        }
        for (index, meal) in ordered.enumerated() { meal.order = index }
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

    /// Remplace les repas prévus d'un jour (régénération) ; repas déjà mangés ou sautés et extras conservés.
    /// Un nouveau repas du même type qu'un repas gardé est écarté (déjeuner mangé : pas de second déjeuner).
    public static func replaceDay(_ day: DayPlan, with dto: DayPlanDTO, in context: ModelContext) throws {
        let kept = day.sortedMeals.filter { $0.status != .planned }
        for meal in day.meals where meal.status == .planned { context.delete(meal) }
        var keptTypes = Dictionary(kept.map { ($0.type, 1) }, uniquingKeysWith: +)
        let fresh = sortedMeals(dto.meals).filter { meal in
            guard let count = keptTypes[meal.type], count > 0 else { return true }
            keptTypes[meal.type] = count - 1
            return false
        }
        let new = fresh.map { Meal(dto: $0, order: 0) }
        day.meals = kept + new
        // Rang par type de repas, puis gardés avant nouveaux.
        let ordered = (kept.map { ($0, 0) } + new.map { ($0, 1) })
            .sorted { ($0.0.type.sortIndex, $0.1) < ($1.0.type.sortIndex, $1.1) }
        for (index, entry) in ordered.enumerated() { entry.0.order = index }
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
        // Courses validées : liste figée telle qu'achetée (spec 019).
        guard !isShoppingValidated(plan, in: context) else { return }
        let checked = Set(plan.shoppingItems.filter(\.isChecked).map(\.key))
        for item in plan.shoppingItems { context.delete(item) }
        plan.shoppingItems = []
        for line in shoppingLines(for: plan, in: context) {
            plan.shoppingItems.append(ShoppingItem(line: line, isChecked: checked.contains(line.key)))
        }
    }

    /// Lignes de courses. Avant validation, repas déjà mangés ou sautés retirés (spec 019) ; `allMeals` : tous
    /// les repas (coût de la semaine comparé au budget).
    static func shoppingLines(for plan: WeeklyPlan, in context: ModelContext, allMeals: Bool = false) -> [ShoppingLine] {
        let owned = (try? context.fetch(FetchDescriptor<Preferences>()))?.first?.supplementList ?? []
        let meals = plan.days.flatMap(\.meals).filter { allMeals || $0.status == .planned }
        let ingredients = meals.flatMap(\.ingredients)
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
    public static func rebuildStaleShoppingList(for plan: WeeklyPlan, in context: ModelContext) {
        guard !isShoppingValidated(plan, in: context) else { return }
        let lines = shoppingLines(for: plan, in: context)
        let keys = Set(lines.map(\.key))
        // Planning actif : quantités (repas mangés, spec 019) et prix (table mise à jour) aussi comparés ;
        // historique figé.
        let values = Set(lines.map { "\($0.key)=\($0.totalQuantity)=\($0.costEur)" })
        let stale = keys != Set(plan.shoppingItems.map(\.key))
            || (plan.isCurrent && values != Set(plan.shoppingItems.map { "\($0.key)=\($0.totalQuantity)=\($0.costEUR)" }))
        if stale { rebuildShoppingList(for: plan, in: context) }
    }

    public static func isShoppingValidated(_ plan: WeeklyPlan, in context: ModelContext) -> Bool {
        ShoppingValidation.find(planID: plan.id, in: context) != nil
    }

    /// Ticket de tous les repas du planning, mangés compris : coût de la semaine face au budget (spec 019).
    public static func fullShoppingSummary(for plan: WeeklyPlan, in context: ModelContext) -> ShoppingSummary {
        ShoppingListBuilder.summary(shoppingLines(for: plan, in: context, allMeals: true))
    }

    /// Repas prévus des plannings actifs remis aux prix de la table (mise à jour de `prices.json`, spec 018) ;
    /// repas mangés ou sautés et historique inchangés. Renvoie le nombre de repas modifiés.
    @discardableResult
    public static func repriceActivePlans(in context: ModelContext, today: LocalDay? = nil) -> Int {
        let owned = (try? context.fetch(FetchDescriptor<Preferences>()))?.first?.ownedSupplementDetails ?? []
        let resolver = NutritionResolver(cache: InMemoryFoodMatchCache(), supplements: owned)
        var changed = 0
        let plans = activePlans(in: context).filter { plan in today.map { plan.endDay >= $0 } ?? true }
        for meal in plans.flatMap(\.days).flatMap(\.meals) where meal.status == .planned {
            let ingredients = meal.ingredients.map { $0.foodCode == nil ? $0 : resolver.priced($0) }
            let cost = BudgetMath.cents(ingredients.reduce(0) { $0 + $1.costEur })
            guard ingredients != meal.ingredients || cost != meal.costEUR else { continue }
            meal.ingredientsData = (try? JSONEncoder().encode(ingredients)) ?? meal.ingredientsData
            meal.costEUR = cost
            changed += 1
        }
        return changed
    }

    /// Supprime un planning et tout ce qui en dépend (jours, repas, extras du journal, courses).
    public static func deletePlan(_ plan: WeeklyPlan, in context: ModelContext) throws {
        let planID = plan.id
        try? context.delete(model: ShoppingValidation.self, where: #Predicate { $0.planID == planID })
        context.delete(plan)
        try context.save()
        // Restes reportés depuis ce planning : courses suivantes recalculées.
        rebuildActiveShoppingLists(in: context)
    }

    private static func sortedMeals(_ meals: [MealDTO]) -> [MealDTO] {
        meals.enumerated()
            .sorted { ($0.element.type.sortIndex, $0.offset) < ($1.element.type.sortIndex, $1.offset) }
            .map(\.element)
    }

    /// Recettes des repas prévus à partir de `today` dont les étapes ne citent pas les quantités du repas :
    /// effacées pour être réécrites. Renvoie le nombre de recettes effacées.
    @discardableResult
    public static func clearStaleRecipes(from today: LocalDay, in context: ModelContext) -> Int {
        var cleared = 0
        for day in activePlans(in: context).flatMap(\.days) where day.day >= today {
            for meal in day.meals where meal.status == .planned && !RecipeConsistency.stepsMatch(meal.dto) {
                meal.steps = []
                cleared += 1
            }
        }
        if cleared > 0 { try? context.save() }
        return cleared
    }

    /// Nettoyage au lancement : tirets cadratins des textes déjà générés, ancien modèle IA par défaut.
    /// Courses des plannings terminés ou en historique figées (spec 019) : déjà faites, et la semaine suivante
    /// déduit leurs restes cochés. Renvoie le nombre de listes figées.
    @discardableResult
    public static func validatePastShopping(today: LocalDay, in context: ModelContext) -> Int {
        var count = 0
        for plan in (try? context.fetch(FetchDescriptor<WeeklyPlan>())) ?? []
        where (!plan.isCurrent || plan.endDay < today) && !isShoppingValidated(plan, in: context) {
            context.insert(ShoppingValidation(planID: plan.id, validatedAt: plan.startDay.startDate(calendar: .current)))
            count += 1
        }
        return count
    }

    public static func cleanUpStoredData(in context: ModelContext, today: LocalDay? = nil) {
        if let today { validatePastShopping(today: today, in: context) }
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
        repriceActivePlans(in: context, today: today)
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
