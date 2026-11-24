import ShreddishCore
import SwiftData
import SwiftUI

/// Période à planifier : premier jour (aujourd'hui ou jusqu'à 13 jours plus tard, spec 006) et dernier jour (1 à 7 jours).
/// Seuls les jours prévus de la période sont remplacés.
struct NewWeekSheet: View {
    let today: LocalDay
    let activePlans: [WeeklyPlan]
    /// Premier jour, nombre de jours, ingrédients à écouler, recettes à replacer.
    let start: (LocalDay, Int, [IngredientDTO], [SavedRecipe]) -> Void
    @Query(sort: \SavedRecipe.savedAt, order: .reverse) var savedRecipes: [SavedRecipe]
    @State private var startDay: LocalDay?
    @State private var endDay: LocalDay?
    /// Recettes sauvegardées à replacer (spec 014) ; par défaut celles mises en attente.
    @State private var pickedRecipes: Set<UUID>?
    /// Questionnaire facultatif : ingrédients à écouler (spec 013).
    @State private var hasPantry = false
    @State private var pantry: [PantryRow] = []

    private var chosen: LocalDay { startDay ?? defaultStart }

    /// Lendemain du dernier planning en cours, pour ne pas archiver la semaine en cours par erreur.
    private var followingDay: LocalDay? {
        guard let next = activePlans.map(\.endDay).max()?.adding(days: 1), next > today,
              next <= today.adding(days: 13) else { return nil }
        return next
    }

    private var defaultStart: LocalDay { followingDay ?? today }

    /// Dernier jour : 7 jours par défaut, au plus 7.
    private var lastDay: LocalDay {
        guard let endDay, chosen <= endDay, endDay <= chosen.adding(days: 6) else { return chosen.adding(days: 6) }
        return endDay
    }

    private var dayCount: Int { lastDay.days(since: chosen) + 1 }

    /// Jours déjà prévus dans la période, remplacés à la génération.
    private var replacedDays: [LocalDay] {
        activePlans.flatMap(\.days).map(\.day).filter { chosen <= $0 && $0 <= lastDay }
    }

    private var replacesActivePlan: Bool { !replacedDays.isEmpty }

    /// Paquets entamés du dernier planning.
    private var suggestions: [IngredientDTO] {
        activePlans.max { $0.startDay < $1.startDay }?.leftovers ?? []
    }

    /// Raccourcis : suite du planning en cours, aujourd'hui, demain, prochain lundi, prochain dimanche.
    private var shortcuts: [(String, LocalDay)] {
        var items: [(String, LocalDay)] = followingDay.map { [(String(localized: "Suite du planning"), $0)] } ?? []
        let others = [
            (String(localized: "Aujourd'hui"), today), (String(localized: "Demain"), today.adding(days: 1)),
            (String(localized: "Lundi prochain"), Format.next(weekday: 2, after: today)),
            (String(localized: "Dimanche prochain"), Format.next(weekday: 1, after: today)),
        ]
        for (label, day) in others where !items.contains(where: { $0.1 == day }) { items.append((label, day)) }
        return items.sorted { $0.1 < $1.1 }
    }

    /// Raccourcis de fin : 7 jours, jusqu'à dimanche, veille du planning suivant.
    private var endShortcuts: [(String, LocalDay)] {
        let candidates = [
            (String(localized: "7 jours"), chosen.adding(days: 6)),
            (String(localized: "Jusqu'à dimanche"), Format.next(weekday: 1, after: chosen)),
            (String(localized: "Avant le planning suivant"), activePlans.map(\.startDay).filter { $0 > chosen }.min()?.adding(days: -1)),
        ]
        var items: [(String, LocalDay)] = []
        for case let (label, day?) in candidates where day >= chosen && day <= chosen.adding(days: 6) {
            if !items.contains(where: { $0.1 == day }) { items.append((label, day)) }
        }
        return items.sorted { $0.1 < $1.1 }
    }

    private var effect: String {
        let replaced = replacedDays
        guard !replaced.isEmpty else { return String(localized: "Aucun jour prévu remplacé.") }
        var text = replaced.count == 1
            ? String(localized: "1 jour prévu remplacé, les autres restent.")
            : String(localized: "\(replaced.count) jours prévus remplacés, les autres restent.")
        if replaced.contains(today) { text += " " + String(localized: "Repas déjà cochés aujourd'hui gardés.") }
        return text
    }

    private var period: String {
        dayCount == 1
            ? String(localized: "Le \(Format.weekdayLong(chosen)), 1 jour.")
            : String(localized: "Du \(Format.weekdayLong(chosen)) au \(Format.weekdayLong(lastDay)), \(dayCount) jours.")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionTitle(title: "Premier jour")
                    dayGrid(shortcuts, selected: chosen, id: "startDay") {
                        startDay = $0
                        endDay = nil
                    }
                    DatePicker(
                        String(localized: "Autre date"),
                        selection: Binding(
                            get: { chosen.startDate(calendar: .current) },
                            set: {
                                startDay = LocalDay(date: $0, calendar: .current)
                                endDay = nil
                            }
                        ),
                        in: today.startDate(calendar: .current)...today.adding(days: 13).startDate(calendar: .current),
                        displayedComponents: .date
                    )
                    .font(Theme.text(.body))
                    .card()
                    SectionTitle(title: "Dernier jour")
                    dayGrid(endShortcuts, selected: lastDay, id: "endDay") { endDay = $0 }
                    DatePicker(
                        String(localized: "Autre date"),
                        selection: Binding(
                            get: { lastDay.startDate(calendar: .current) },
                            set: { endDay = LocalDay(date: $0, calendar: .current) }
                        ),
                        in: chosen.startDate(calendar: .current)...chosen.adding(days: 6).startDate(calendar: .current),
                        displayedComponents: .date
                    )
                    .font(Theme.text(.body))
                    .card()
                    .accessibilityIdentifier("endDayPicker")
                    Text("\(period) \(effect)")
                        .font(Theme.text(.footnote, replacesActivePlan ? .semibold : .regular))
                        .foregroundStyle(replacesActivePlan ? Theme.tomato : Theme.muted)
                        .accessibilityIdentifier("periodSummary")
                    PantryQuestion(hasPantry: $hasPantry, rows: $pantry, suggestions: suggestions)
                    if !savedRecipes.isEmpty {
                        RecipePicker(recipes: savedRecipes, picked: Binding(
                            get: { pickedRecipes ?? Set(savedRecipes.filter(\.isQueued).map(\.id)) },
                            set: { pickedRecipes = $0 }
                        ))
                    }
                }
                .padding(20)
            }
            .paperBackground()
            .navigationTitle("Planifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Générer") {
                        let picked = pickedRecipes ?? Set(savedRecipes.filter(\.isQueued).map(\.id))
                        let ingredients = hasPantry ? pantry.compactMap(\.ingredient) : []
                        start(chosen, dayCount, ingredients, savedRecipes.filter { picked.contains($0.id) })
                    }
                        .accessibilityIdentifier("startGeneration")
                }
            }
        }
    }

    private func dayGrid(
        _ items: [(String, LocalDay)], selected: LocalDay, id: String, select: @escaping (LocalDay) -> Void
    ) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.1) { label, day in
                let isSelected = day == selected
                Button {
                    select(day)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label).font(Theme.text(.subheadline, .semibold))
                        Text(Format.weekdayLong(day)).font(Theme.text(.caption))
                    }
                    .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(isSelected ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier(id)
            }
        }
    }
}
