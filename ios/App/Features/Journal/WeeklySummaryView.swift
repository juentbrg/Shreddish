import ShreddishCore
import SwiftData
import SwiftUI

/// Bilan hebdomadaire : moyennes réelles et adhérence (FR-018b).
struct WeeklySummaryView: View {
    @Environment(AppModel.self) private var model
    let plan: WeeklyPlan

    var body: some View {
        let summary = Totals.weeklySummary(days: plan.sortedDays.map(\.log), clock: model.clock)
        List {
            Section {
                if let rate = summary.adherenceRate {
                    LabeledContent("Adhérence", value: Format.percent(rate))
                        .font(.title3.bold())
                        .accessibilityIdentifier("adherence")
                    LabeledContent("Repas mangés", value: "\(summary.eatenCount) / \(summary.plannedCount)")
                } else {
                    Text("Aucun jour terminé. Le jour compte à partir de 21 h.")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Jours comptés", value: "\(summary.elapsedDays)")
            }
            if summary.elapsedDays > 0, let targets = plan.targets {
                Section("Moyenne par jour") {
                    let average = summary.averageActual
                    TargetGauge(title: "Calories", value: average.kcal, target: Double(targets.targetKcal), format: Format.kcal)
                    TargetGauge(title: "Protéines", value: average.proteinG, target: Double(targets.proteinG), format: Format.grams)
                    TargetGauge(title: "Glucides", value: average.carbsG, target: Double(targets.carbsG), format: Format.grams)
                    TargetGauge(title: "Lipides", value: average.fatG, target: Double(targets.fatG), format: Format.grams)
                }
            }
            Section("Par jour") {
                ForEach(plan.sortedDays) { day in
                    LabeledContent(Format.day(day.day, calendar: model.clock.calendar)) {
                        VStack(alignment: .trailing) {
                            Text(Format.kcal(day.actualTotals.kcal))
                            Text("prévu \(Format.kcal(day.plannedTotals.kcal))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .themedList()
        .navigationTitle("Bilan de la semaine")
    }
}
