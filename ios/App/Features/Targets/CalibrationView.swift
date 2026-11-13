import ShreddishCore
import SwiftData
import SwiftUI

/// État et réglages de la calibration par les pesées (spec 002, FR-106 à FR-109).
struct CalibrationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query var profiles: [Profile]
    @State private var refresh = 0

    var body: some View {
        List {
            if let profile = profiles.first {
                let outcome = { _ = refresh; return CalibrationService.outcome(profile: profile, context: context, clock: model.clock) }()
                statusSection(outcome, profile: profile)
                settingsSection(profile, outcome: outcome)
                Section {
                    Text(
                        "Sur les 4 dernières semaines, l'app compare ce que tu as mangé (jours entièrement cochés "
                            + "dans le journal) à l'évolution de ton poids : 1 kg ≈ 7 700 kcal. La dépense réelle "
                            + "en découle. Chaque semaine, la cible avance de la moitié de l'écart, 150 kcal au plus."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .themedList()
        .navigationTitle("Calibration")
    }

    @ViewBuilder
    private func statusSection(_ outcome: CalibrationOutcome?, profile: Profile) -> some View {
        switch outcome {
        case let .estimate(estimate):
            Section("Estimation") {
                LabeledContent("Dépense réelle", value: Format.kcal(estimate.observedTdee))
                    .accessibilityIdentifier("observedTdee")
                if let formula = CalibrationService.formulaTdee(profile: profile, clock: model.clock) {
                    LabeledContent("Formule", value: Format.kcal(formula))
                    LabeledContent("Écart", value: Format.percent((estimate.observedTdee - formula) / formula, signed: true))
                }
                LabeledContent("Apport moyen", value: Format.kcal(estimate.averageIntake))
                let sign = estimate.weeklyChangeKg >= 0 ? "+" : "−"
                LabeledContent("Poids", value: "\(sign)\(Format.number(abs(estimate.weeklyChangeKg), digits: 2)) kg / semaine")
                LabeledContent("Jours de journal complets", value: "\(estimate.completeDays)")
            }
        case let .insufficientData(completeDays, weightSpanDays):
            Section {
                progressRow(
                    "Jours de journal complets", value: completeDays, total: EnergyCalibration.requiredCompleteDays
                )
                progressRow(
                    "Jours couverts par les pesées", value: weightSpanDays, total: EnergyCalibration.requiredWeightSpanDays
                )
            } header: {
                Text("Pas encore assez de données")
            } footer: {
                Text("Coche tous tes repas et pèse-toi 2 fois par semaine.")
            }
        case let .implausible(observed):
            Section("Estimation écartée") {
                Label(
                    "Dépense de \(Format.kcal(observed)), trop loin de la formule : extras oubliés ?",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
        case nil:
            Section { Text("Profil incomplet.") }
        }
    }

    private func settingsSection(_ profile: Profile, outcome: CalibrationOutcome?) -> some View {
        @Bindable var profile = profile
        return Section {
            Toggle("Ajuster automatiquement chaque semaine", isOn: $profile.isAutoCalibrationOn)
            LabeledContent(
                "Ajustement actuel",
                value: "\((profile.tdeeAdjustmentKcal ?? 0) >= 0 ? "+" : "−") \(Format.kcal(abs(profile.tdeeAdjustmentKcal ?? 0)))"
            )
            .accessibilityIdentifier("currentAdjustment")
            if let last = profile.lastCalibrationAt {
                LabeledContent("Dernier ajustement", value: last.formatted(.dateTime.day().month().locale(Format.locale)))
            }
            if case let .estimate(estimate) = outcome {
                Button("Recalibrer maintenant") {
                    model.calibrationMessage = CalibrationService.apply(estimate, to: profile, clock: model.clock)
                    try? context.save()
                    refresh += 1
                }
            }
            if profile.tdeeAdjustmentKcal != nil {
                Button("Réinitialiser l'ajustement", role: .destructive) {
                    profile.tdeeAdjustmentKcal = nil
                    profile.lastCalibrationAt = nil
                    model.calibrationMessage = nil
                    try? context.save()
                    refresh += 1
                }
            }
        } header: {
            Text("Réglages")
        }
    }

    private func progressRow(_ title: String, value: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(min(value, total)) / \(total)").monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: Double(min(value, total)), total: Double(total))
        }
        .accessibilityElement(children: .combine)
    }
}
