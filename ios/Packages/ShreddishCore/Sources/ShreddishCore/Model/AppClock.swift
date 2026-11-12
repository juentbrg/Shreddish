import Foundation
import Synchronization

/// Source de « maintenant » pour toute logique de date, injectée pour les tests (research R12).
public protocol AppClock: Sendable {
    var now: Date { get }
    /// Calendrier de l'utilisateur ; son `timeZone` est celui de l'horloge.
    var calendar: Calendar { get }
}

extension AppClock {
    /// Jour local de `now`.
    public var today: LocalDay { LocalDay(date: now, calendar: calendar) }

    /// Minutes depuis minuit local.
    public var minuteOfDay: Int {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// Horloge de l'appareil, calendrier et fuseau courants.
public struct SystemClock: AppClock {
    public init() {}

    public var now: Date { Date() }
    public var calendar: Calendar { Calendar.autoupdatingCurrent }
}

/// Horloge figée jusqu'à déplacement, pour les tests et les UI tests.
public final class FixedClock: AppClock {
    private let state: Mutex<Date>
    public let calendar: Calendar

    public init(now: Date, timeZone: TimeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt) {
        state = Mutex(now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        self.calendar = calendar
    }

    /// Horloge réglée à `hour`:`minute` du jour `day`.
    public convenience init(
        day: LocalDay, hour: Int = 12, minute: Int = 0,
        timeZone: TimeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = calendar.date(from: DateComponents(
            year: day.year, month: day.month, day: day.day, hour: hour, minute: minute
        )) ?? .distantPast
        self.init(now: date, timeZone: timeZone)
    }

    public var now: Date { state.withLock { $0 } }

    public func set(_ date: Date) {
        state.withLock { $0 = date }
    }
}
