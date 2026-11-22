import EventKit
import ShreddishCore
import SwiftUI

/// Partage de la liste de courses (spec 017, FR-1706) : texte par rayon, ou une liste dans Rappels.
enum ShoppingExport {
    /// Articles encore à acheter, par rayon.
    static func toBuy(_ plan: WeeklyPlan) -> [(aisle: Aisle, items: [ShoppingItem])] {
        let items = plan.shoppingItems.filter { !$0.isChecked && $0.totalQuantity > 0 }
        return Dictionary(grouping: items, by: \.aisle)
            .sorted { $0.key.sortIndex < $1.key.sortIndex }
            .map { ($0.key, $0.value.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) }
    }

    static func line(_ item: ShoppingItem) -> String {
        "\(item.name) — \(Format.packing(item.packing, quantity: item.totalQuantity, unit: item.unit))"
    }

    /// « Courses du 22 nov. au 28 nov. », puis un bloc par rayon.
    static func text(_ plan: WeeklyPlan) -> String {
        let title = String(localized: "Courses du \(Format.shortDate(plan.startDay)) au \(Format.shortDate(plan.endDay))")
        let blocks = toBuy(plan).map { group in
            ([group.aisle.label] + group.items.map { "• \(line($0))" }).joined(separator: "\n")
        }
        return ([title] + blocks).joined(separator: "\n\n")
    }

    enum RemindersError: Error { case denied, noSource }

    /// Crée (ou complète) la liste « Courses Shreddish » dans Rappels ; renvoie le nombre d'articles ajoutés.
    static func sendToReminders(_ lines: [String]) async throws -> Int {
        let store = EKEventStore()
        guard try await store.requestFullAccessToReminders() else { throw RemindersError.denied }
        let name = String(localized: "Courses Shreddish")
        let list: EKCalendar
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == name }) {
            list = existing
        } else {
            guard let source = store.defaultCalendarForNewReminders()?.source else { throw RemindersError.noSource }
            list = EKCalendar(for: .reminder, eventStore: store)
            list.title = name
            list.source = source
            try store.saveCalendar(list, commit: true)
        }
        let open = await withCheckedContinuation { (continuation: CheckedContinuation<Set<String>, Never>) in
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: Set((reminders ?? []).compactMap(\.title)))
            }
        }
        var added = 0
        for line in lines where !open.contains(line) {
            let reminder = EKReminder(eventStore: store)
            reminder.title = line
            reminder.calendar = list
            try store.save(reminder, commit: false)
            added += 1
        }
        try store.commit()
        return added
    }
}
