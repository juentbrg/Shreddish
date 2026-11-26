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

/// D'où vient la cible : métabolisme, activité, sport, calibration, dépense, ajustement, cible.
struct CalculationLadder: View {
    let breakdown: CalculationBreakdown
    let targets: NutritionTargets
    let profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("D'où vient ta cible")
                .font(Theme.text(.subheadline, .bold))
                .accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: 6) {
                chip(String(localized: "\(Format.number(breakdown.bmr, digits: 0)) base"))
                if let daily = breakdown.dailyActivityFactor {
                    step("× \(Format.number(daily, digits: 2))")
                    step(String(localized: "+ \(Format.number(breakdown.exerciseKcalPerDay ?? 0, digits: 0)) sport"))
                } else {
                    step("× \(Format.number(breakdown.activityFactor, digits: 3))")
                }
                if let calibration = breakdown.calibrationKcal {
                    step(String(localized: "\(calibration >= 0 ? "+" : "−") \(Format.number(abs(calibration), digits: 0)) pesées"))
                }
                step("=")
                chip(Format.number(breakdown.tdee, digits: 0))
                step(Format.percent(breakdown.calorieAdjustment, signed: true))
                step("=")
                chip(Format.kcal(Double(targets.targetKcal)), strong: true)
            }
            .accessibilityElement(children: .combine)
            if targets.floorApplied {
                Text("Plancher de sécurité : \(Format.kcal(breakdown.floorKcal))")
                    .font(Theme.text(.caption))
                    .foregroundStyle(Theme.tomatoInk)
            }
            let protein = Format.number(breakdown.proteinPerKg), fat = Format.number(breakdown.fatPerKg)
            Text("Protéines \(protein) g/kg · lipides \(fat) g/kg · glucides le reste")
                .font(Theme.text(.caption))
                .foregroundStyle(Theme.muted)
            Text("Formule Mifflin-St Jeor : 10 × poids + 6,25 × taille − 5 × âge \(profile.sex == .male ? "+ 5" : "− 161").")
                .font(Theme.text(.caption))
                .foregroundStyle(Theme.muted)
        }
        .foregroundStyle(Theme.ink)
        .card(padding: 16, radius: 22)
    }

    private func chip(_ text: String, strong: Bool = false) -> some View {
        Text(text)
            .font(Theme.text(.footnote, strong ? .bold : .medium))
            .monospacedDigit()
            .foregroundStyle(strong ? Theme.paper : Theme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(strong ? Theme.ink : Theme.line, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func step(_ text: String) -> some View {
        Text(text).font(Theme.text(.footnote)).foregroundStyle(Theme.muted).padding(.vertical, 4)
    }
}

/// Éléments en ligne, retour à la ligne quand la largeur manque.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let added = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += added
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
