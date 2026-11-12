import Foundation

/// Activité quotidienne hors sport : métier, déplacements, pas (FR-101).
public enum DailyActivity: String, Codable, Sendable, CaseIterable {
    case sedentary
    case light
    case active
    case veryActive = "very_active"

    /// Multiplicateur du métabolisme de base, sport exclu.
    public var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.3
        case .active: 1.4
        case .veryActive: 1.5
        }
    }
}

/// Intensité moyenne des séances (FR-102). MET : dépense / dépense au repos.
public enum TrainingIntensity: String, Codable, Sendable, CaseIterable {
    case light
    case moderate
    case intense

    public var met: Double {
        switch self {
        case .light: 3.5
        case .moderate: 5
        case .intense: 6.5
        }
    }
}

/// Charge d'entraînement hebdomadaire (FR-102, FR-103).
public struct TrainingLoad: Sendable, Equatable, Codable {
    public static let sessionsRange = 0...14
    public static let minutesRange = 15...240
    /// Valeurs proposées à l'onboarding.
    public static let defaultLoad = TrainingLoad(sessionsPerWeek: 3, minutesPerSession: 60, intensity: .moderate)

    public var sessionsPerWeek: Int
    public var minutesPerSession: Int
    public var intensity: TrainingIntensity

    public init(sessionsPerWeek: Int, minutesPerSession: Int, intensity: TrainingIntensity) {
        self.sessionsPerWeek = sessionsPerWeek
        self.minutesPerSession = minutesPerSession
        self.intensity = intensity
    }

    public var isValid: Bool {
        Self.sessionsRange.contains(sessionsPerWeek) && Self.minutesRange.contains(minutesPerSession)
    }

    /// Dépense ajoutée par une séance, au-delà du repos : (MET − 1) × poids × heures.
    public func kcalPerSession(weightKg: Double) -> Double {
        (intensity.met - 1) * weightKg * Double(minutesPerSession) / 60
    }

    /// Dépense sport moyenne par jour sur la semaine.
    public func kcalPerDay(weightKg: Double) -> Double {
        kcalPerSession(weightKg: weightKg) * Double(sessionsPerWeek) / 7
    }
}
