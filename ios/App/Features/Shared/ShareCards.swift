import ShreddishCore
import SwiftUI

/// Cartes partageables au format story 9:16 (spec 017, FR-1718), sans donnée sensible par défaut.
enum ShareCardSize {
    static let width: CGFloat = 360
    static let height: CGFloat = 640
}

/// « Ma semaine » : 7 jours de plats, kcal par jour, coût face au budget.
struct WeekShareCard: View {
    let plan: WeeklyPlan
    let budget: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ma semaine")
                .font(Theme.display(30, .heavy, relativeTo: .largeTitle))
                .foregroundStyle(Theme.onAccent)
            if let targets = plan.targets {
                Text("\(Format.kcal(Double(targets.targetKcal))) par jour · \(targets.proteinG) g de protéines")
                    .font(Theme.text(.subheadline, .semibold))
                    .foregroundStyle(Theme.onAccent.opacity(0.9))
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(plan.sortedDays) { day in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Format.weekdayLong(day.day).capitalized)
                            .font(Theme.text(.caption, .bold))
                            .foregroundStyle(Theme.accent)
                        Text(day.sortedMeals.filter { $0.type != .snack }.map(\.name).joined(separator: " · "))
                            .font(Theme.text(.caption))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            let cost = plan.shoppingSummary.weekCostEur
            Text("\(Format.euros(cost)) de courses pour la semaine\(cost <= budget ? String(localized: ", dans le budget") : "")")
                .font(Theme.text(.subheadline, .semibold))
                .foregroundStyle(Theme.onAccent)
            Spacer(minLength: 0)
            ShareWatermark()
        }
        .padding(22)
        .frame(width: ShareCardSize.width, height: ShareCardSize.height, alignment: .topLeading)
        .background(Theme.accent)
    }
}

/// Progrès des 30 derniers jours, photos avant / après seulement si l'utilisateur les ajoute.
struct ProgressShareCard: View {
    let report: MonthlyReport
    var before: UIImage?
    var after: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("30 jours de sèche")
                .font(Theme.display(30, .heavy, relativeTo: .largeTitle))
                .foregroundStyle(Theme.onAccent)
            if let before, let after {
                HStack(spacing: 8) {
                    photo(before, label: "Avant")
                    photo(after, label: "Maintenant")
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                if let change = report.weightChange {
                    stat("\(change > 0 ? "+" : "")\(Format.number(change)) kg", "sur la balance")
                }
                if let waist = report.waistChange {
                    stat("\(waist > 0 ? "+" : "")\(Format.number(waist)) cm", "de tour de taille")
                }
                if let adherence = report.adherence {
                    stat("\(Int((adherence * 100).rounded())) %", "des repas suivis")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Spacer(minLength: 0)
            ShareWatermark()
        }
        .padding(22)
        .frame(width: ShareCardSize.width, height: ShareCardSize.height, alignment: .topLeading)
        .background(Theme.accent)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value).font(Theme.display(28, .heavy, relativeTo: .title)).foregroundStyle(Theme.ink)
            Text(label).font(Theme.text(.subheadline)).foregroundStyle(Theme.muted)
        }
    }

    private func photo(_ image: UIImage, label: String) -> some View {
        VStack(spacing: 4) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: 150, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(label).font(Theme.text(.caption, .bold)).foregroundStyle(Theme.onAccent)
        }
    }
}

/// Ticket de courses réel contre estimé, coût par repas : l'argument budget d'une sèche (FR-1718).
struct ReceiptShareCard: View {
    let comparison: ReceiptComparison
    /// Repas du planning ; `portions` : personnes du foyer en portions.
    let meals: Int
    let portions: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mes courses de sèche")
                .font(Theme.display(30, .heavy, relativeTo: .largeTitle))
                .foregroundStyle(Theme.onAccent)
            VStack(alignment: .leading, spacing: 12) {
                row("Estimé par l'app", Format.euros(comparison.estimatedEUR), muted: true)
                row("Payé en caisse", Format.euros(comparison.paidEUR), muted: false)
                Divider().overlay(Theme.line)
                Text(ReceiptSection.verdict(comparison))
                    .font(Theme.text(.headline, .bold))
                    .foregroundStyle(comparison.difference <= 0 ? Theme.accent : Theme.tomatoInk)
                if comparison.budgetEUR > 0 {
                    Text(comparison.withinBudget
                        ? String(localized: "Dans le budget de \(Format.euros(comparison.budgetEUR)).")
                        : String(localized: "Budget prévu : \(Format.euros(comparison.budgetEUR))."))
                        .font(Theme.text(.subheadline))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            if meals > 0 {
                let perMeal = comparison.paidEUR / (Double(meals) * max(portions, 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.euros(perMeal))
                        .font(Theme.display(56, .heavy, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.onAccent)
                    Text("par repas, \(meals) repas planifiés")
                        .font(Theme.text(.subheadline, .semibold))
                        .foregroundStyle(Theme.onAccent.opacity(0.9))
                }
            }
            Spacer(minLength: 0)
            ShareWatermark()
        }
        .padding(22)
        .frame(width: ShareCardSize.width, height: ShareCardSize.height, alignment: .topLeading)
        .background(Theme.accent)
    }

    private func row(_ label: LocalizedStringKey, _ value: String, muted: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Theme.text(.subheadline)).foregroundStyle(Theme.muted)
            Spacer()
            Text(value)
                .font(Theme.display(muted ? 22 : 28, .heavy, relativeTo: .title))
                .foregroundStyle(muted ? Theme.muted : Theme.ink)
        }
    }
}

private struct ShareWatermark: View {
    var body: some View {
        Text("Shreddish")
            .font(Theme.display(16, .bold, relativeTo: .headline))
            .foregroundStyle(Theme.onAccent.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Aperçu d'une carte et partage de son image.
struct ShareCardSheet<Card: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var scale
    let title: String
    let card: Card

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                card
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .scaleEffect(0.8)
                    .frame(width: ShareCardSize.width * 0.8, height: ShareCardSize.height * 0.8)
                if let image = rendered {
                    ShareLink(item: image, preview: SharePreview(title, image: image)) {
                        Label("Partager", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PillButtonStyle())
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("shareCard")
                }
            }
            .frame(maxHeight: .infinity)
            .paperBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
        }
    }

    @MainActor private var rendered: Image? {
        let renderer = ImageRenderer(content: card.environment(\.colorScheme, .light))
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}
