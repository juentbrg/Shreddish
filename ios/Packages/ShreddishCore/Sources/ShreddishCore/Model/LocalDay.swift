import Foundation

/// Jour civil sans fuseau (« quel jour », pas « quel instant »), repris de Nowtick.
///
/// Arithmétique en jours par numéro de jour julien : indépendante des changements d'heure.
public struct LocalDay: Hashable, Comparable, Sendable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Jour sur lequel tombe `date` dans `calendar` (et son fuseau).
    public init(date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Clé entière stable `yyyymmdd`, stockée en base et triable.
    public var key: Int { year * 10_000 + month * 100 + day }

    public init(key: Int) {
        self.init(year: key / 10_000, month: (key / 100) % 100, day: key % 100)
    }

    /// Numéro de jour julien (calendrier grégorien proleptique).
    public var julianDayNumber: Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    public init(julianDayNumber jdn: Int) {
        let a = jdn + 32044
        let b = (4 * a + 3) / 146_097
        let c = a - 146_097 * b / 4
        let d = (4 * c + 3) / 1461
        let e = c - 1461 * d / 4
        let m = (5 * e + 2) / 153
        self.init(
            year: 100 * b + d - 4800 + m / 10,
            month: m + 3 - 12 * (m / 10),
            day: e - (153 * m + 2) / 5 + 1
        )
    }

    public func adding(days: Int) -> LocalDay {
        LocalDay(julianDayNumber: julianDayNumber + days)
    }

    /// Nombre de jours de `other` à `self` (positif si `self` est après).
    public func days(since other: LocalDay) -> Int {
        julianDayNumber - other.julianDayNumber
    }

    /// Minuit local de ce jour.
    public func startDate(calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        lhs.key < rhs.key
    }
}
