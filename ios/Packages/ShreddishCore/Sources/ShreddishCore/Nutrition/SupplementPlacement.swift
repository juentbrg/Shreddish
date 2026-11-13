import Foundation

/// Prises de compléments « dose » (créatine, vitamines…) placées par l'application (spec 010).
public enum SupplementPlacement {
    /// Texte de prise par complément « dose » : « Créatine : 5 g » ou « Oméga-3 : 1 gelule, 2 fois par jour ».
    public static func doses(_ supplements: [OwnedSupplement]) -> [String] {
        supplements.filter { $0.kind == .dose }.map { supplement in
            var text = supplement.name
            if let dose = supplement.dose { text += " : \(dose)" }
            if let times = supplement.dosesPerDay, times > 1 { text += ", \(times) fois par jour" }
            return text
        }
    }

    /// Repas qui reçoit les prises : premier repas à partir de l'heure d'entraînement, sinon le déjeuner,
    /// sinon le premier repas.
    public static func hostIndex(in meals: [MealDTO], trainingTimeMinutes: Int?) -> Int? {
        guard !meals.isEmpty else { return nil }
        if let training = trainingTimeMinutes,
           let index = meals.indices.filter({ (minutes(meals[$0].time) ?? -1) >= training })
               .min(by: { (minutes(meals[$0].time) ?? 0) < (minutes(meals[$1].time) ?? 0) }) {
            return index
        }
        return meals.firstIndex { $0.type == .lunch } ?? 0
    }

    static func minutes(_ time: String?) -> Int? {
        guard let parts = time?.split(separator: ":"), parts.count == 2, let hours = Int(parts[0]),
              let minutes = Int(parts[1]) else { return nil }
        return hours * 60 + minutes
    }
}
