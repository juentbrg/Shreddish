import ShreddishCore
import SwiftUI

/// Carte de tête des courses : ticket estimé, coût de la semaine face au budget (specs 013 et 018).
struct ShoppingBudgetCard: View {
    let summary: ShoppingSummary
    let preferences: Preferences?

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
                budgetBar(cost: cost, preferences: preferences)
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
        }
        .foregroundStyle(Theme.ink)
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    /// Coût de la semaine sur le plafond (budget + tolérance), repère au budget.
    private func budgetBar(cost: Double, preferences: Preferences) -> some View {
        let ceiling = max(preferences.budgetCeiling, 1)
        let over = cost > preferences.weeklyBudget + 0.005
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule().fill(over ? Theme.tomato : Theme.success).frame(width: proxy.size.width * min(cost / ceiling, 1))
                Rectangle().fill(Theme.ink)
                    .frame(width: 2, height: 18)
                    .offset(x: proxy.size.width * min(preferences.weeklyBudget / ceiling, 1) - 1)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func badge(cost: Double, preferences: Preferences) -> some View {
        let gap = cost - preferences.weeklyBudget
        let beyond = cost > preferences.budgetCeiling + 0.005
        let text: String = if gap <= 0.005 {
            String(localized: "Dans le budget")
        } else if beyond {
            String(localized: "\(Format.euros(gap)) au-dessus du budget")
        } else {
            String(localized: "Dans la tolérance")
        }
        return Text(text)
            .font(Theme.text(.caption, .bold))
            .foregroundStyle(gap <= 0.005 ? Theme.success : Theme.tomatoInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(gap <= 0.005 ? Theme.successSoft : Theme.tomatoSoft, in: Capsule())
    }
}
