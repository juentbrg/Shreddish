import Foundation
import SwiftData

/// Planning de 7 jours consécutifs, du jour de génération à J+6 (FR-009, FR-013).
@Model
public final class WeeklyPlan {
    @Attribute(.unique) public var id: UUID
    /// `LocalDay.key` du jour de génération.
    public var startDayKey: Int
    public var createdAt: Date
    /// `NutritionTargets` encodées : cibles utilisées à la génération.
    public var targetsData: Data
    /// `[PrepSessionDTO]` encodées ; vide si batch cooking désactivé.
    public var prepSessionsData: Data
    /// Un seul planning courant ; les autres restent consultables.
    public var isCurrent: Bool
    @Relationship(deleteRule: .cascade, inverse: \DayPlan.plan) public var days: [DayPlan] = []
    @Relationship(deleteRule: .cascade, inverse: \ShoppingItem.plan) public var shoppingItems: [ShoppingItem] = []

    public init(startDay: LocalDay, createdAt: Date, targets: NutritionTargets, prepSessions: [PrepSessionDTO]) {
        id = UUID()
        startDayKey = startDay.key
        self.createdAt = createdAt
        targetsData = (try? JSONEncoder().encode(targets)) ?? Data()
        prepSessionsData = (try? JSONEncoder().encode(prepSessions)) ?? Data()
        isCurrent = true
    }

    public var startDay: LocalDay { LocalDay(key: startDayKey) }
    /// Dernier jour : J+6, ou plus tôt si une semaine suivante a repris les derniers jours (spec 006).
    public var endDay: LocalDay { days.map(\.day).max() ?? startDay.adding(days: 6) }

    public func contains(_ day: LocalDay) -> Bool { startDay <= day && day <= endDay }

    public var targets: NutritionTargets? {
        try? JSONDecoder().decode(NutritionTargets.self, from: targetsData)
    }

    public var prepSessions: [PrepSessionDTO] {
        get { (try? JSONDecoder().decode([PrepSessionDTO].self, from: prepSessionsData)) ?? [] }
        set { prepSessionsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    public var sortedDays: [DayPlan] { days.sorted { $0.offset < $1.offset } }

    public func day(_ localDay: LocalDay) -> DayPlan? {
        days.first { $0.dayKey == localDay.key }
    }

    public var dto: WeekPlanDTO {
        WeekPlanDTO(prepSessions: prepSessions, days: sortedDays.map(\.dto))
    }
}

@Model
public final class DayPlan {
    public var dayKey: Int
    /// 0-6 depuis le début du planning.
    public var offset: Int
    public var plan: WeeklyPlan?
    @Relationship(deleteRule: .cascade, inverse: \Meal.day) public var meals: [Meal] = []
    @Relationship(deleteRule: .cascade, inverse: \ExtraEntry.day) public var extras: [ExtraEntry] = []

    public init(day: LocalDay, offset: Int) {
        dayKey = day.key
        self.offset = offset
    }

    public var day: LocalDay { LocalDay(key: dayKey) }
    public var sortedMeals: [Meal] { meals.sorted { $0.order < $1.order } }
    public var sortedExtras: [ExtraEntry] { extras.sorted { $0.loggedAt < $1.loggedAt } }

    public var plannedTotals: MacroTotals { meals.map(\.macros).sum() }
    public var plannedCostEUR: Double { meals.reduce(0) { $0 + $1.costEUR } }

    public var log: DayLog {
        DayLog(
            day: day,
            meals: sortedMeals.map { LoggedMeal(macros: $0.macros, status: $0.status) },
            extras: sortedExtras.map(\.macros)
        )
    }

    public var actualTotals: MacroTotals { Totals.actual(log) }

    public var dto: DayPlanDTO {
        DayPlanDTO(dayOffset: offset, meals: sortedMeals.map(\.dto))
    }
}

@Model
public final class Meal {
    public var typeRaw: String
    public var name: String
    /// `[IngredientDTO]` encodés.
    public var ingredientsData: Data
    public var steps: [String]
    public var prepMinutes: Int
    public var costEUR: Double
    public var kcal: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var prepSessionRef: Int?
    /// Heure conseillée « HH:mm » (spec 004, SchemaV4).
    public var time: String?
    public var statusRaw: String
    public var statusChangedAt: Date?
    /// Position dans la journée.
    public var order: Int
    public var day: DayPlan?

    public init(dto: MealDTO, order: Int) {
        typeRaw = dto.type.rawValue
        name = dto.name
        ingredientsData = (try? JSONEncoder().encode(dto.ingredients)) ?? Data()
        steps = dto.steps
        prepMinutes = dto.prepMinutes
        costEUR = dto.costEur
        kcal = dto.kcal
        proteinG = dto.proteinG
        carbsG = dto.carbsG
        fatG = dto.fatG
        prepSessionRef = dto.prepSessionRef
        time = dto.time
        statusRaw = MealStatus.planned.rawValue
        self.order = order
    }

    public var type: MealType { MealType(rawValue: typeRaw) ?? .lunch }

    public var status: MealStatus {
        get { MealStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    public var ingredients: [IngredientDTO] {
        (try? JSONDecoder().decode([IngredientDTO].self, from: ingredientsData)) ?? []
    }

    public var macros: MacroTotals {
        MacroTotals(kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
    }

    public var dto: MealDTO {
        MealDTO(
            type: type, name: name, ingredients: ingredients, steps: steps, prepMinutes: prepMinutes,
            costEur: costEUR, kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG, prepSessionRef: prepSessionRef,
            time: time
        )
    }

    public func setStatus(_ status: MealStatus, at date: Date) {
        self.status = status
        statusChangedAt = date
    }
}

/// Extra libre ajouté au journal d'un jour (FR-018).
@Model
public final class ExtraEntry {
    public var name: String
    public var quantityLabel: String?
    public var kcal: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var loggedAt: Date
    public var day: DayPlan?

    public init(name: String, quantityLabel: String?, macros: MacroTotals, loggedAt: Date) {
        self.name = name
        self.quantityLabel = quantityLabel
        kcal = max(0, macros.kcal)
        proteinG = max(0, macros.proteinG)
        carbsG = max(0, macros.carbsG)
        fatG = max(0, macros.fatG)
        self.loggedAt = loggedAt
    }

    public var macros: MacroTotals {
        MacroTotals(kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
    }
}

/// Ligne de la liste de courses d'un planning (FR-015).
@Model
public final class ShoppingItem {
    public var plan: WeeklyPlan?
    public var name: String
    /// Nom normalisé + unité ; conserve `isChecked` entre reconstructions.
    public var key: String
    public var totalQuantity: Double
    public var unitRaw: String
    public var aisleRaw: String
    public var costEUR: Double
    public var isChecked: Bool

    public init(line: ShoppingLine, isChecked: Bool) {
        name = line.name
        key = line.key
        totalQuantity = line.totalQuantity
        unitRaw = line.unit.rawValue
        aisleRaw = line.aisle.rawValue
        costEUR = line.costEur
        self.isChecked = isChecked
    }

    public var unit: MeasureUnit { MeasureUnit(rawValue: unitRaw) ?? .g }
    public var aisle: Aisle { Aisle(rawValue: aisleRaw) ?? .autre }

    /// Nom sans tirets et rayon corrigé d'après le nom (spec 008), pour les listes déjà enregistrées.
    func cleanUp(with clean: (String) -> String) {
        if clean(name) != name { name = clean(name) }
        let corrected = AisleClassifier.corrected(name: name, aisle: aisle)
        if corrected != aisle { aisleRaw = corrected.rawValue }
    }
}

/// Pesée, une par jour (US6).
@Model
public final class WeightEntry {
    @Attribute(.unique) public var dayKey: Int
    public var weightKg: Double
    public var recordedAt: Date

    public init(day: LocalDay, weightKg: Double, recordedAt: Date) {
        dayKey = day.key
        self.weightKg = weightKg
        self.recordedAt = recordedAt
    }

    public var day: LocalDay { LocalDay(key: dayKey) }
    public var point: WeightPoint { WeightPoint(day: day, weightKg: weightKg) }
}
