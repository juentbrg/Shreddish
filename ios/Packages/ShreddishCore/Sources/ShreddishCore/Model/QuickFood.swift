import Foundation
import SwiftData

/// Aliment du journal rapide (spec 017, FR-1716) : récent ou favori, ajouté en un toucher.
/// Prêt pour CloudKit : valeurs par défaut partout, aucun attribut unique.
@Model
public final class QuickFood {
    public var id = UUID()
    public var name = ""
    /// Valeurs pour 100 g (ou 100 ml).
    public var kcalPer100 = 0.0
    public var proteinPer100 = 0.0
    public var carbsPer100 = 0.0
    public var fatPer100 = 0.0
    /// Dernière portion saisie, en g.
    public var lastGrams = 100.0
    public var barcode: String?
    public var foodCode: Int?
    public var isFavorite = false
    public var lastUsedAt = Date()
    public var useCount = 0

    public init(name: String, per100g: MacroTotals, grams: Double, barcode: String? = nil, foodCode: Int? = nil, usedAt: Date) {
        self.name = name
        kcalPer100 = per100g.kcal
        proteinPer100 = per100g.proteinG
        carbsPer100 = per100g.carbsG
        fatPer100 = per100g.fatG
        lastGrams = grams
        self.barcode = barcode
        self.foodCode = foodCode
        lastUsedAt = usedAt
    }

    public var per100g: MacroTotals {
        MacroTotals(kcal: kcalPer100, proteinG: proteinPer100, carbsG: carbsPer100, fatG: fatPer100)
    }

    public func macros(grams: Double) -> MacroTotals {
        let factor = grams / 100
        return MacroTotals(
            kcal: kcalPer100 * factor, proteinG: proteinPer100 * factor, carbsG: carbsPer100 * factor, fatG: fatPer100 * factor
        )
    }
}

/// Journal rapide : un aliment pesé devient un extra du jour et un récent.
@MainActor
public enum QuickLog {
    /// Extra ajouté au jour, aliment rapide créé ou mis à jour (même code-barres, code Ciqual ou nom).
    @discardableResult
    public static func log(
        name: String, per100g: MacroTotals, grams: Double, barcode: String? = nil, foodCode: Int? = nil,
        to day: DayPlan, at date: Date, in context: ModelContext
    ) -> ExtraEntry {
        let food = find(name: name, barcode: barcode, foodCode: foodCode, in: context)
            ?? QuickFood(name: name, per100g: per100g, grams: grams, barcode: barcode, foodCode: foodCode, usedAt: date)
        if food.modelContext == nil { context.insert(food) }
        food.lastGrams = grams
        food.lastUsedAt = date
        food.useCount += 1
        let extra = ExtraEntry(
            name: name, quantityLabel: "\(Int(grams.rounded())) g", macros: food.macros(grams: grams).rounded, loggedAt: date
        )
        day.extras.append(extra)
        try? context.save()
        return extra
    }

    public static func find(name: String, barcode: String?, foodCode: Int?, in context: ModelContext) -> QuickFood? {
        let foods = (try? context.fetch(FetchDescriptor<QuickFood>())) ?? []
        if let barcode, let match = foods.first(where: { $0.barcode == barcode }) { return match }
        if let foodCode, let match = foods.first(where: { $0.foodCode == foodCode }) { return match }
        let key = TextNormalizer.singular(name)
        return foods.first { TextNormalizer.singular($0.name) == key }
    }

    /// Favoris d'abord, puis les plus récents.
    public static func suggestions(in context: ModelContext, limit: Int = 12) -> [QuickFood] {
        let foods = (try? context.fetch(FetchDescriptor<QuickFood>())) ?? []
        return Array(foods.sorted {
            $0.isFavorite != $1.isFavorite ? $0.isFavorite : $0.lastUsedAt > $1.lastUsedAt
        }.prefix(limit))
    }
}
