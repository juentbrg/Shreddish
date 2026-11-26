import ShreddishCore
import SwiftUI

/// Carte de tête des courses : ticket estimé, coût de la semaine face au budget (specs 013 et 018).
struct ShoppingBudgetCard: View {
    let summary: ShoppingSummary
    let preferences: Preferences?
    /// Avancement des courses ; `nil` une fois validées.
    var progress: ShoppingProgress?

    var body: some View {
        let cost = summary.weekCostEur
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ticket estimé").font(Theme.text(.footnote, .medium)).foregroundStyle(Theme.muted)
                Spacer()
                if let preferences { badge(cost: cost, preferences: preferences) }
            }
            Text(Format.euros(summary.checkoutEur))
                .font(Theme.display(38, .heavy, relativeTo: .largeTitle))
                .monospacedDigit()
                .accessibilityIdentifier("weekCost")
            if let preferences {
                BudgetBar(cost: cost, preferences: preferences).frame(height: 10)
                HStack(alignment: .firstTextBaseline) {
                    Text("Budget \(Format.euros(preferences.weeklyBudget)) · tolérance \(Format.percent(preferences.tolerance))")
                    Spacer(minLength: 8)
                    if summary.keptEur >= 0.5 {
                        Text("\(Format.euros(summary.keptEur)) te resteront")
                    }
                }
                .font(Theme.text(.caption))
                .foregroundStyle(Theme.muted)
            }
            if summary.wastedEur >= 0.5 {
                Text("Dont \(Format.euros(summary.wastedEur)) de restes à finir vite (paquets entamés)")
                    .font(Theme.text(.caption))
                    .foregroundStyle(Theme.tomatoInk)
            }
            if let progress {
                Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 4)
                ProgressSection(progress: progress)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func badge(cost: Double, preferences: Preferences) -> some View {
        let status = BudgetStatus(cost: cost, preferences: preferences)
        return Text(status.text)
            .font(Theme.text(.caption, .bold))
            .foregroundStyle(status.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(status.inBudget ? Theme.successSoft : Theme.tomatoSoft, in: Capsule())
    }
}

/// Articles cochés et prix de ce qui reste à acheter (specs 018 et 019).
struct ShoppingProgress {
    let remaining: Double
    let checked: Int
    let total: Int
}

/// Reste à acheter, mis à jour à chaque coche, et barre des articles cochés.
private struct ProgressSection: View {
    let progress: ShoppingProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.checked == progress.total ? "Tout est coché" : "Reste à acheter")
                        .font(Theme.text(.subheadline, .bold))
                    Text("\(progress.checked) sur \(progress.total) articles cochés")
                        .font(Theme.text(.caption))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(Format.euros(progress.remaining))
                    .font(Theme.display(24, .heavy, relativeTo: .title2))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: progress.remaining)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("remainingCost")
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(Theme.ink)
                        .frame(width: proxy.size.width * CGFloat(progress.checked) / CGFloat(max(progress.total, 1)))
                        .animation(.snappy, value: progress.checked)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
    }
}

/// Position du coût face au budget et à la tolérance.
struct BudgetStatus {
    let inBudget: Bool
    let text: String

    init(cost: Double, preferences: Preferences) {
        let gap = cost - preferences.weeklyBudget
        inBudget = gap <= 0.005
        text = if inBudget {
            String(localized: "Dans le budget")
        } else if cost > preferences.budgetCeiling + 0.005 {
            String(localized: "\(Format.euros(gap)) au-dessus du budget")
        } else {
            String(localized: "Dans la tolérance")
        }
    }

    var ink: Color { inBudget ? Theme.success : Theme.tomatoInk }
}

/// Coût de la semaine sur le plafond (budget + tolérance), repère au budget.
struct BudgetBar: View {
    let cost: Double
    let preferences: Preferences

    var body: some View {
        let ceiling = max(preferences.budgetCeiling, 1)
        let over = cost > preferences.weeklyBudget + 0.005
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule().fill(over ? Theme.tomato : Theme.success).frame(width: proxy.size.width * min(cost / ceiling, 1))
                Rectangle().fill(Theme.ink)
                    .frame(width: 2, height: proxy.size.height + 8)
                    .offset(x: proxy.size.width * min(preferences.weeklyBudget / ceiling, 1) - 1)
            }
        }
        .accessibilityHidden(true)
    }
}
