import Foundation
import ShreddishCore
import SwiftUI

/// Formats d'affichage en français.
enum Format {
    static let locale = Locale(identifier: "fr_FR")

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
        case .g: value >= 1000 ? "\(number(value / 1000, digits: 2)) kg" : "\(Int(value.rounded())) g"
        case .ml: value >= 1000 ? "\(number(value / 1000, digits: 2)) l" : "\(Int(value.rounded())) ml"
        case .piece: "× \(number(value))"
        }
    }

    static func day(_ day: LocalDay, calendar: Calendar, style: Date.FormatStyle? = nil) -> String {
        let date = day.startDate(calendar: calendar)
        let format = style ?? Date.FormatStyle(date: .omitted, time: .omitted).weekday(.wide).day().month(.abbreviated)
        return date.formatted(format.locale(locale)).capitalizedFirst
    }

    /// « Du mercredi 11 nov. au mardi 17 nov. »
    static func range(_ plan: WeeklyPlan, calendar: Calendar) -> String {
        let start = day(plan.startDay, calendar: calendar).lowercased()
        let end = day(plan.endDay, calendar: calendar).lowercased()
        return "Du \(start) au \(end)"
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
    var label: String { self == .male ? "Homme" : "Femme" }
}

extension ActivityLevel {
    var label: String {
        switch self {
        case .sedentary: "Sédentaire"
        case .light: "Légèrement actif"
        case .moderate: "Modérément actif"
        case .active: "Actif"
        case .veryActive: "Très actif"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: "Bureau, peu ou pas de sport"
        case .light: "Sport 1 à 3 fois par semaine"
        case .moderate: "Sport 3 à 5 fois par semaine"
        case .active: "Sport 6 à 7 fois par semaine"
        case .veryActive: "Sport intense quotidien ou métier physique"
        }
    }
}

extension Goal {
    var label: String {
        switch self {
        case .cut: "Sèche"
        case .bulk: "Prise de masse"
        case .recomp: "Recomposition"
        }
    }
}

extension MealType {
    var label: String {
        switch self {
        case .breakfast: "Petit-déjeuner"
        case .lunch: "Déjeuner"
        case .dinner: "Dîner"
        case .snack: "Collation"
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
        case .fruitsLegumes: "Fruits et légumes"
        case .viandePoisson: "Viande et poisson"
        case .cremerie: "Crèmerie"
        case .epicerie: "Épicerie"
        case .surgeles: "Surgelés"
        case .boulangerie: "Boulangerie"
        case .autre: "Autre"
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
            .font(.footnote)
            .foregroundStyle(.secondary)
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
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .labelStyle(.titleAndIcon)
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
                Text(title).font(.subheadline)
                Spacer()
                Text("\(format(value)) / \(format(target))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(value, target * 1.5), total: max(target, 1))
                .tint(target > 0 && abs(value - target) / target > Totals.offTargetThreshold && value > target ? .orange : .accentColor)
        }
        .accessibilityElement(children: .combine)
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
