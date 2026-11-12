import Charts
import ShreddishCore
import SwiftData
import SwiftUI

/// Pesées, courbe, alerte de rythme et recalcul des cibles (US6, FR-016, FR-017).
struct WeightView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.dayKey) var entries: [WeightEntry]
    @Query var profiles: [Profile]
    @State private var input = ""
    @State private var pendingRecalc: Double?

    var body: some View {
        NavigationStack {
            List {
                entrySection
                if let weight = pendingRecalc, let profile = profiles.first {
                    recalcSection(weight: weight, profile: profile)
                }
                trendSection
                if entries.count >= 2 { chartSection }
                historySection
            }
            .navigationTitle("Poids")
            .keyboardDoneButton()
        }
    }

    private var entrySection: some View {
        Section {
            HStack {
                TextField("Poids du jour (kg)", text: $input)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("weightInput")
                Button("Enregistrer", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(parsedInput == nil)
                    .accessibilityIdentifier("saveWeight")
            }
        } footer: {
            Text("Une pesée par jour, idéalement le matin à jeun. Une nouvelle saisie remplace celle du jour.")
        }
    }

    private func recalcSection(weight: Double, profile: Profile) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recalculer tes cibles avec \(Format.number(weight)) kg ?")
                    .font(.headline)
                if let current = profile.targets(clock: model.clock) {
                    let kcal = Format.kcal(Double(current.targetKcal))
                    Text("Cible actuelle : \(kcal) (calculée sur \(Format.number(profile.weightKg)) kg).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Recalculer mes cibles") {
                        profile.weightKg = weight
                        try? context.save()
                        pendingRecalc = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("recalcTargets")
                    Button("Plus tard") { pendingRecalc = nil }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var trendSection: some View {
        let points = entries.map(\.point)
        if let rate = WeightTrend.weeklyLossRate(points) {
            Section("Rythme") {
                LabeledContent(
                    rate >= 0 ? "Perte moyenne" : "Prise moyenne",
                    value: "\(Format.number(abs(rate), digits: 2)) % / semaine"
                )
                if let goal = profiles.first?.goal, WeightTrend.isTooFast(points, goal: goal) {
                    Label(
                        "Rythme rapide : plus de 1 % du poids par semaine. "
                            + "Risque de perte musculaire, pense à remonter un peu les calories.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("tooFast")
                }
            }
        }
    }

    private var chartSection: some View {
        Section("Évolution") {
            Chart(entries) { entry in
                LineMark(
                    x: .value("Date", entry.day.startDate(calendar: model.clock.calendar)),
                    y: .value("Poids", entry.weightKg)
                )
                .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value("Date", entry.day.startDate(calendar: model.clock.calendar)),
                    y: .value("Poids", entry.weightKg)
                )
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 200)
            .accessibilityLabel("Courbe de poids, \(entries.count) pesées")
        }
    }

    private var historySection: some View {
        Section("Historique") {
            ForEach(entries.reversed()) { entry in
                LabeledContent(Format.day(entry.day, calendar: model.clock.calendar), value: "\(Format.number(entry.weightKg)) kg")
            }
            .onDelete { offsets in
                let reversed = Array(entries.reversed())
                for index in offsets { context.delete(reversed[index]) }
                try? context.save()
            }
        }
    }

    private var parsedInput: Double? {
        guard let value = Format.parse(input), NutritionCalculator.weightRange.contains(value) else { return nil }
        return value
    }

    private func save() {
        guard let weight = parsedInput else { return }
        let today = model.clock.today
        if let existing = entries.first(where: { $0.dayKey == today.key }) {
            existing.weightKg = weight
            existing.recordedAt = model.clock.now
        } else {
            context.insert(WeightEntry(day: today, weightKg: weight, recordedAt: model.clock.now))
        }
        try? context.save()
        input = ""
        if let profile = profiles.first, abs(profile.weightKg - weight) >= 0.1 {
            pendingRecalc = weight
        }
    }
}
