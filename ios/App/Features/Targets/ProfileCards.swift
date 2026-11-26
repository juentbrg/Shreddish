import ShreddishCore
import SwiftData
import SwiftUI

/// Poids actuel, évolution sur 3 semaines, petite courbe et accès à la pesée (design « Écrans clairs »).
struct WeightSummaryCard: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \WeightEntry.dayKey) private var entries: [WeightEntry]
    let profile: Profile
    let weighIn: () -> Void

    var body: some View {
        let today = model.clock.today
        let recent = entries.filter { $0.day >= today.adding(days: -21) }
        let current = entries.last?.weightKg ?? profile.weightKg
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Poids").font(Theme.text(.footnote)).foregroundStyle(Theme.muted)
                Text("\(Format.number(current)) kg").font(Theme.display(26, .heavy, relativeTo: .title2))
                if let first = recent.first, recent.count > 1 {
                    let delta = current - first.weightKg
                    Text("\(delta <= 0 ? "−" : "+")\(Format.number(abs(delta))) kg en \(Self.span(first.day, today))")
                        .font(Theme.text(.caption, .bold))
                        .foregroundStyle(delta <= 0 ? Theme.success : Theme.tomatoInk)
                } else if entries.last?.day != today {
                    Text("Pas de pesée aujourd'hui").font(Theme.text(.caption)).foregroundStyle(Theme.muted)
                }
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
            Sparkline(values: recent.map(\.weightKg))
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 52)
            Button("Peser", action: weighIn)
                .buttonStyle(CompactButtonStyle())
                .accessibilityIdentifier("weighIn")
        }
        .foregroundStyle(Theme.ink)
        .padding(.vertical, 14)
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private static func span(_ from: LocalDay, _ to: LocalDay) -> String {
        let days = to.key == from.key ? 0 : max(1, to.days(since: from))
        return days >= 7 ? String(localized: "\(days / 7) sem.") : String(localized: "\(days) j")
    }
}

/// Courbe simple, sans axes ; rien sous 2 points.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            if values.count > 1, let low = values.min(), let high = values.max() {
                let range = max(high - low, 0.5)
                let points = values.enumerated().map { index, value in
                    CGPoint(
                        x: proxy.size.width * CGFloat(index) / CGFloat(values.count - 1),
                        y: 4 + (proxy.size.height - 8) * CGFloat((high - value) / range)
                    )
                }
                let color = values.last! <= values.first! ? Theme.success : Theme.tomato
                Path { path in path.addLines(points) }
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                Circle().fill(color).frame(width: 8, height: 8).position(points.last!)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Tuile de réglage du profil : icône, titre, détail.
struct ProfileTile: View {
    let title: LocalizedStringKey
    let detail: String
    let symbol: String
    let colors: (background: Color, ink: Color)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colors.ink)
                .frame(width: 36, height: 36)
                .background(colors.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            Text(title).font(Theme.text(.subheadline, .bold)).foregroundStyle(Theme.ink)
            Text(detail).font(Theme.text(.caption)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// D'où vient la cible, ligne par ligne comme un ticket : base, activité, sport, pesées, dépense, objectif, cible.
struct CalculationLadder: View {
    let breakdown: CalculationBreakdown
    let targets: NutritionTargets
    let profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("D'où vient ta cible")
                .font(Theme.text(.subheadline, .bold))
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 6)
            row(Text("Métabolisme de base"), detail: "Mifflin-St Jeor", value: Format.number(breakdown.bmr, digits: 0))
            if let daily = breakdown.dailyActivityFactor {
                row(
                    Text("Activité au quotidien"), detail: "× \(Format.number(daily, digits: 2))",
                    value: Self.signed(breakdown.bmr * (daily - 1))
                )
                row(Text("Sport"), detail: String(localized: "moyenne par jour"), value: Self.signed(breakdown.exerciseKcalPerDay ?? 0))
            } else {
                row(
                    Text("Activité"), detail: "× \(Format.number(breakdown.activityFactor, digits: 3))",
                    value: Self.signed(breakdown.bmr * (breakdown.activityFactor - 1))
                )
            }
            if let calibration = breakdown.calibrationKcal, abs(calibration) >= 1 {
                row(Text("Ajusté par tes pesées"), detail: nil, value: Self.signed(calibration))
            }
            row(Text("Dépense estimée"), detail: nil, value: Format.number(breakdown.tdee, digits: 0), strong: true)
            row(
                Text(profile.goal.label), detail: Format.percent(breakdown.calorieAdjustment, signed: true),
                value: Self.signed(breakdown.adjustedKcal - breakdown.tdee)
            )
            if targets.floorApplied {
                row(Text("Plancher de sécurité"), detail: nil, value: Self.signed(breakdown.floorKcal - breakdown.adjustedKcal))
            }
            HStack {
                Text("Ta cible").font(Theme.text(.subheadline, .bold))
                Spacer()
                Text(Format.kcal(Double(targets.targetKcal)))
                    .font(Theme.display(20, .heavy, relativeTo: .title3))
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.paper)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
            .padding(.top, 10)
            let protein = Format.number(breakdown.proteinPerKg), fat = Format.number(breakdown.fatPerKg)
            Text("Protéines \(protein) g/kg · lipides \(fat) g/kg · glucides le reste")
                .font(Theme.text(.caption))
                .foregroundStyle(Theme.muted)
                .padding(.top, 10)
        }
        .foregroundStyle(Theme.ink)
        .card(padding: 16, radius: 22)
    }

    private func row(_ title: Text, detail: String?, value: String, strong: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                title.font(Theme.text(.subheadline, strong ? .bold : .regular))
                if let detail {
                    Text(detail).font(Theme.text(.caption)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Text(value)
                    .font(Theme.text(.subheadline, strong ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(strong ? Theme.ink : Theme.muted)
            }
            .padding(.vertical, 9)
            .accessibilityElement(children: .combine)
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    private static func signed(_ value: Double) -> String {
        let rounded = value.rounded()
        return "\(rounded < 0 ? "−" : "+") \(Format.number(abs(rounded), digits: 0))"
    }
}
