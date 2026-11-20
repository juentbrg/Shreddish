import Foundation
import ShreddishCore
import SwiftUI

/// Formats d'affichage dans la langue de l'appareil.
enum Format {
    /// Langue et région de l'appareil (spec 017, FR-1712).
    static var locale: Locale { .autoupdatingCurrent }

    static func kcal(_ value: Double) -> String {
        "\(Int(value.rounded()).formatted(.number.locale(locale))) kcal"
    }

    static func grams(_ value: Double) -> String {
        "\(Int(value.rounded())) g"
    }

    static func euros(_ value: Double) -> String {
        value.formatted(.currency(code: "EUR").locale(locale))
    }

    static func percent(_ value: Double, signed: Bool = false) -> String {
        let style = FloatingPointFormatStyle<Double>.Percent.percent.locale(locale).precision(.fractionLength(0))
        return signed ? value.formatted(style.sign(strategy: .always())) : value.formatted(style)
    }

    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(0...digits)))
    }

    static func quantity(_ value: Double, unit: MeasureUnit) -> String {
        switch unit {
        case .g: value >= 1000 ? String(localized: "\(number(value / 1000, digits: 2)) kg") : "\(Int(value.rounded())) g"
        case .ml: value >= 1000 ? String(localized: "\(number(value / 1000, digits: 2)) l") : "\(Int(value.rounded())) ml"
        case .piece: String(localized: "× \(number(value))")
        }
    }

    /// Paquets à acheter : « 2 × 400 g », « 1 × 12 », ou la quantité au détail (spec 013).
    static func packing(_ packing: Packing, quantity: Double, unit: MeasureUnit) -> String {
        guard let size = packing.packSize, packing.packCount > 0 else { return Self.quantity(quantity, unit: unit) }
        let pack = unit == .piece ? number(size) : Self.quantity(size, unit: unit)
        return String(localized: "\(packing.packCount) × \(pack)")
    }

    static func day(_ day: LocalDay, calendar: Calendar, style: Date.FormatStyle? = nil) -> String {
        let date = day.startDate(calendar: calendar)
        let format = style ?? Date.FormatStyle(date: .omitted, time: .omitted).weekday(.wide).day().month(.abbreviated)
        return date.formatted(format.locale(locale)).capitalizedFirst
    }

    /// « JEU. » pour le sélecteur de jours.
    static func weekdayShort(_ day: LocalDay) -> String {
        day.startDate(calendar: frenchCalendar)
            .formatted(Date.FormatStyle(date: .omitted, time: .omitted).weekday(.abbreviated).locale(locale))
            .replacingOccurrences(of: ".", with: "")
            .uppercased()
    }

    /// « jeudi 12 novembre ».
    static func weekdayLong(_ day: LocalDay) -> String {
        day.startDate(calendar: frenchCalendar)
            .formatted(Date.FormatStyle(date: .omitted, time: .omitted).weekday(.wide).day().month(.wide).locale(locale))
    }

    /// « 15 nov. »
    static func shortDate(_ day: LocalDay) -> String {
        day.startDate(calendar: frenchCalendar)
            .formatted(Date.FormatStyle(date: .omitted, time: .omitted).day().month(.abbreviated).locale(locale))
    }

    /// Prochain jour de la semaine (1 = dimanche … 7 = samedi), strictement après `day`.
    static func next(weekday: Int, after day: LocalDay) -> LocalDay {
        let current = frenchCalendar.component(.weekday, from: day.startDate(calendar: frenchCalendar))
        let delta = (weekday - current + 7) % 7
        return day.adding(days: delta == 0 ? 7 : delta)
    }

    private static var frenchCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar
    }

    /// « Du mercredi 11 nov. au mardi 17 nov. »
    static func range(_ plan: WeeklyPlan, calendar: Calendar) -> String {
        let start = day(plan.startDay, calendar: calendar).lowercased()
        let end = day(plan.endDay, calendar: calendar).lowercased()
        return String(localized: "Du \(start) au \(end)")
    }

    /// Part d'un repas mangé : « Mangé en entier », « Mangé aux ¾ ».
    static func fraction(_ value: Double) -> String {
        switch value {
        case 0.75: String(localized: "Mangé aux ¾")
        case 0.5: String(localized: "Mangé à moitié")
        case 0.25: String(localized: "Mangé au ¼")
        default: String(localized: "Mangé en entier")
        }
    }

    /// « 1 portion », « 2,75 portions ».
    static func portion(_ value: Double) -> String {
        let count = number(value, digits: 2)
        return value > 1 ? String(localized: "\(count) portions") : String(localized: "\(count) portion")
    }

    /// « 19:30 » depuis des minutes après minuit.
    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60 % 24, minutes % 60)
    }

    /// « 16 h 30 », « 16 h ».
    static func duration(_ minutes: Int) -> String {
        minutes % 60 == 0 ? String(localized: "\(minutes / 60) h") : "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    /// Analyse un nombre saisi avec virgule ou point.
    static func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Libellés

extension Sex {
    var label: String { self == .male ? String(localized: "Homme") : "Femme" }
}

extension ActivityLevel {
    var label: String {
        switch self {
        case .sedentary: String(localized: "Sédentaire")
        case .light: String(localized: "Légèrement actif")
        case .moderate: String(localized: "Modérément actif")
        case .active: String(localized: "Actif")
        case .veryActive: String(localized: "Très actif")
        }
    }

    var detail: String {
        switch self {
        case .sedentary: String(localized: "Bureau, peu ou pas de sport")
        case .light: String(localized: "Sport 1 à 3 fois par semaine")
        case .moderate: String(localized: "Sport 3 à 5 fois par semaine")
        case .active: String(localized: "Sport 6 à 7 fois par semaine")
        case .veryActive: String(localized: "Sport intense quotidien ou métier physique")
        }
    }
}

extension DailyActivity {
    var label: String {
        switch self {
        case .sedentary: String(localized: "Sédentaire")
        case .light: String(localized: "Peu actif")
        case .active: String(localized: "Actif")
        case .veryActive: String(localized: "Très actif")
        }
    }

    var detail: String {
        switch self {
        case .sedentary: String(localized: "Bureau, moins de 5 000 pas.")
        case .light: String(localized: "5 000 à 7 500 pas.")
        case .active: String(localized: "7 500 à 10 000 pas, ou souvent debout.")
        case .veryActive: String(localized: "Plus de 10 000 pas, ou métier physique.")
        }
    }
}

extension TrainingIntensity {
    var label: String {
        switch self {
        case .light: String(localized: "Légère")
        case .moderate: String(localized: "Modérée")
        case .intense: String(localized: "Intense")
        }
    }

    var detail: String {
        switch self {
        case .light: String(localized: "Yoga, mobilité, muscu légère.")
        case .moderate: String(localized: "Muscu classique, vélo, course tranquille.")
        case .intense: String(localized: "Muscu à l'échec, escalade, HIIT, combat.")
        }
    }
}

extension Diet {
    var label: String {
        switch self {
        case .vegetarian: String(localized: "Végétarien")
        case .vegan: String(localized: "Vegan")
        case .pescatarian: String(localized: "Pescétarien")
        case .halal: String(localized: "Halal")
        case .kosher: String(localized: "Casher")
        case .glutenFree: String(localized: "Sans gluten")
        case .lactoseFree: String(localized: "Sans lactose")
        }
    }
}

extension Goal {
    var label: String {
        switch self {
        case .cut: String(localized: "Sèche")
        case .bulk: String(localized: "Prise de masse")
        case .recomp: String(localized: "Recomposition")
        }
    }
}

extension MealType {
    var label: String {
        switch self {
        case .breakfast: String(localized: "Petit-déjeuner")
        case .lunch: String(localized: "Déjeuner")
        case .dinner: String(localized: "Dîner")
        case .snack: String(localized: "Collation")
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "carrot"
        }
    }
}

extension Aisle {
    var label: String {
        switch self {
        case .fruitsLegumes: String(localized: "Fruits et légumes")
        case .viandePoisson: String(localized: "Viande et poisson")
        case .cremerie: String(localized: "Crèmerie")
        case .epicerie: String(localized: "Épicerie")
        case .surgeles: String(localized: "Surgelés")
        case .boulangerie: String(localized: "Boulangerie")
        case .autre: String(localized: "Autre")
        }
    }
}

// MARK: - Composants

/// Ligne kcal + macros compacte.
struct MacroLine: View {
    let macros: MacroTotals

    var body: some View {
        let protein = Format.grams(macros.proteinG)
        let carbs = Format.grams(macros.carbsG)
        let fat = Format.grams(macros.fatG)
        Text("\(Format.kcal(macros.kcal)) · P \(protein) · G \(carbs) · L \(fat)")
            .font(Theme.text(.footnote))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(
                "\(Format.kcal(macros.kcal)), protéines \(protein), glucides \(carbs), lipides \(fat)"
            )
    }
}

/// Badge d'avertissement (hors cible, hors budget).
struct WarningBadge: View {
    let text: String
    var systemImage = "exclamationmark.triangle.fill"

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(Theme.text(.caption, .semibold))
            .foregroundStyle(Theme.tomatoInk)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.tomatoSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Comparaison valeur / cible avec barre de progression.
struct TargetGauge: View {
    let title: String
    let value: Double
    let target: Double
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(LocalizedStringKey(title)).font(Theme.text(.subheadline))
                Spacer()
                Text("\(format(value)) / \(format(target))")
                    .font(Theme.text(.subheadline).monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
            ProgressView(value: min(value, target * 1.5), total: max(target, 1))
                .tint(target > 0 && abs(value - target) / target > Totals.offTargetThreshold && value > target ? Theme.tomato : Theme.green)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Bouton de suppression visible sur une ligne (en plus du balayage).
struct DeleteRowButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.tomato)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Supprimer \(label)")
    }
}

// MARK: - Clavier

extension View {
    /// Bouton « OK » au-dessus du clavier numérique (pas de touche retour sur le pavé décimal).
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .accessibilityIdentifier("keyboardDone")
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
