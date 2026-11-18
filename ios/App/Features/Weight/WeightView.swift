import Charts
import ShreddishCore
import SwiftData
import SwiftUI

/// Suivi du poids, ouvert depuis le profil : pesée, rythme, courbe, historique (US6, FR-016, FR-017).
struct WeightView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.dayKey) var entries: [WeightEntry]
    @Query var profiles: [Profile]

    var body: some View {
        List {
            WeightEntrySection()
            WeightTrendSection(entries: entries, goal: profiles.first?.goal)
            if entries.count >= 2 { chartSection }
            historySection
        }
        .themedList()
        .navigationTitle("Suivi du poids")
        .keyboardDoneButton()
    }

    private var chartSection: some View {
        ThemedSection("Évolution") {
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
        ThemedSection("Historique") {
            ForEach(entries.reversed()) { entry in
                HStack {
                    LabeledContent(Format.day(entry.day, calendar: model.clock.calendar), value: "\(Format.number(entry.weightKg)) kg")
                    DeleteRowButton(label: "la pesée") {
                        context.delete(entry)
                        try? context.save()
                    }
                }
            }
            .onDelete { offsets in
                let reversed = Array(entries.reversed())
                for index in offsets { context.delete(reversed[index]) }
                try? context.save()
            }
        }
    }
}

/// Pesée du jour et proposition de recalcul des cibles (profil et suivi du poids).
struct WeightEntrySection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.dayKey) var entries: [WeightEntry]
    @Query var profiles: [Profile]
    @State private var input = ""
    @State private var pendingRecalc: Double?

    var body: some View {
        Section {
            HStack {
                TextField("Poids du jour (kg)", text: $input)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("weightInput")
                Button("Enregistrer", action: save)
                    .buttonStyle(CompactButtonStyle())
                    .disabled(parsedInput == nil)
                    .accessibilityIdentifier("saveWeight")
            }
        } header: {
            ListHeader {
                Text("Pesée")
            }
        } footer: {
            ListFooter {
                if let last = entries.last {
                    Text("Dernière pesée : \(Format.number(last.weightKg)) kg, \(Format.day(last.day, calendar: model.clock.calendar)). "
                        + "Une par jour, le matin à jeun.")
                } else {
                    Text("Une pesée par jour, le matin à jeun.")
                }
            }
        }
        if let weight = pendingRecalc, let profile = profiles.first {
            recalcSection(weight: weight, profile: profile)
        }
    }

    private func recalcSection(weight: Double, profile: Profile) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recalculer tes cibles avec \(Format.number(weight)) kg ?")
                    .font(Theme.text(.headline, .semibold))
                if let current = profile.targets(clock: model.clock) {
                    let kcal = Format.kcal(Double(current.targetKcal))
                    Text("Cible actuelle : \(kcal) (calculée sur \(Format.number(profile.weightKg)) kg).")
                        .font(Theme.text(.subheadline))
                        .foregroundStyle(Theme.muted)
                }
                HStack {
                    Button("Recalculer mes cibles") {
                        profile.weightKg = weight
                        try? context.save()
                        pendingRecalc = nil
                    }
                    .buttonStyle(CompactButtonStyle())
                    .accessibilityIdentifier("recalcTargets")
                    Button("Plus tard") { pendingRecalc = nil }
                        .buttonStyle(CompactButtonStyle(prominent: false))
                }
            }
            .padding(.vertical, 4)
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

/// Rythme de perte ou de prise et alerte si trop rapide.
struct WeightTrendSection: View {
    let entries: [WeightEntry]
    let goal: Goal?

    var body: some View {
        let points = entries.map(\.point)
        if let rate = WeightTrend.weeklyLossRate(points) {
            ThemedSection("Rythme") {
                LabeledContent(
                    rate >= 0 ? "Perte moyenne" : "Prise moyenne",
                    value: "\(Format.number(abs(rate), digits: 2)) % / semaine"
                )
                if let goal, WeightTrend.isTooFast(points, goal: goal) {
                    Label(
                        "Rythme rapide : plus de 1 % du poids par semaine. "
                            + "Risque de perte musculaire, pense à remonter un peu les calories.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(Theme.tomato)
                    .accessibilityIdentifier("tooFast")
                }
            }
        }
    }
}
