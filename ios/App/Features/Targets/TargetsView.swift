import ShreddishCore
import SwiftData
import SwiftUI

/// Cibles kcal et macros, détail du calcul (US1, FR-002 à FR-005).
struct TargetsView: View {
    @Environment(AppModel.self) private var model
    @Query var profiles: [Profile]

    var body: some View {
        NavigationStack {
            Group {
                if let profile = profiles.first, let targets = profile.targets(clock: model.clock) {
                    content(profile: profile, targets: targets)
                } else {
                    ContentUnavailableView("Profil incomplet", systemImage: "person.crop.circle.badge.exclamationmark")
                }
            }
            .themedList()
            .navigationTitle("Mes cibles")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Réglages", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("settings")
                }
            }
        }
    }

    private func content(profile: Profile, targets: NutritionTargets) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.goal.label.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(Format.kcal(Double(targets.targetKcal)))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .accessibilityIdentifier("targetKcal")
                    Text("par jour")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                macroRow("Protéines", grams: targets.proteinG, kcalPerGram: 4, color: .red)
                macroRow("Glucides", grams: targets.carbsG, kcalPerGram: 4, color: .blue)
                macroRow("Lipides", grams: targets.fatG, kcalPerGram: 9, color: .yellow)
            }
            if let message = model.calibrationMessage {
                Section {
                    Label(message, systemImage: "scalemass.fill")
                        .foregroundStyle(.tint)
                        .accessibilityIdentifier("calibrationMessage")
                }
            }
            if profile.dailyActivity == nil {
                Section {
                    NavigationLink {
                        ProfileEditView()
                    } label: {
                        Label(
                            "Précise ton activité (séances, intensité, pas) pour une dépense plus juste.",
                            systemImage: "figure.strengthtraining.traditional"
                        )
                    }
                }
            }
            if !targets.warnings.isEmpty {
                Section {
                    ForEach(targets.warnings, id: \.self) { warning in
                        Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            breakdownSection(targets.breakdown, targets: targets, profile: profile)
            Section {
                NavigationLink("Modifier mon profil") { ProfileEditView() }
                NavigationLink("Ajuster les macros") { MacroSettingsView() }
                NavigationLink {
                    CalibrationView()
                } label: {
                    LabeledContent("Calibration par les pesées", value: profile.isAutoCalibrationOn ? "Auto" : "Manuelle")
                }
                .accessibilityIdentifier("calibration")
            }
            Section {
                Text("Outil personnel, pas un avis médical. Valeurs estimées par des formules standard.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func macroRow(_ title: String, grams: Int, kcalPerGram: Int, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
            Text(title)
            Spacer()
            Text("\(grams) g")
                .bold()
                .monospacedDigit()
            Text("\(grams * kcalPerGram) kcal")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 80, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func breakdownSection(_ breakdown: CalculationBreakdown, targets: NutritionTargets, profile: Profile) -> some View {
        Section("Détail du calcul") {
            LabeledContent("Métabolisme de base", value: Format.kcal(breakdown.bmr))
            if let daily = breakdown.dailyActivityFactor {
                LabeledContent("Activité hors sport", value: "× \(Format.number(daily, digits: 2))")
                LabeledContent("Sport (moyenne par jour)", value: "+ \(Format.kcal(breakdown.exerciseKcalPerDay ?? 0))")
            } else {
                LabeledContent("Activité", value: "× \(Format.number(breakdown.activityFactor, digits: 3))")
            }
            if let calibration = breakdown.calibrationKcal {
                LabeledContent(
                    "Calibration (pesées)",
                    value: "\(calibration >= 0 ? "+" : "−") \(Format.kcal(abs(calibration)))"
                )
            }
            LabeledContent("Dépense estimée", value: Format.kcal(breakdown.tdee))
            LabeledContent(
                "Ajustement \(profile.goal.label.lowercased())",
                value: Format.percent(breakdown.calorieAdjustment, signed: true)
            )
            if targets.floorApplied {
                LabeledContent("Plancher de sécurité", value: Format.kcal(breakdown.floorKcal))
            }
            LabeledContent("Protéines", value: "\(Format.number(breakdown.proteinPerKg)) g/kg")
            LabeledContent("Lipides", value: "\(Format.number(breakdown.fatPerKg)) g/kg")
            LabeledContent("Glucides", value: "le reste")
            Text("Formule Mifflin-St Jeor : 10 × poids + 6,25 × taille − 5 × âge \(profile.sex == .male ? "+ 5" : "− 161").")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

extension TargetWarning {
    var message: String {
        switch self {
        case .floorApplied: "Cible ramenée au plancher de sécurité : descendre plus bas n'est pas conseillé."
        case .fatReduced: "Lipides abaissés (minimum 0,6 g/kg) pour garder des glucides."
        case .carbsAtZero: "Protéines et lipides couvrent déjà toute la cible : glucides à 0. Revois tes réglages."
        }
    }
}

struct ProfileEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query var profiles: [Profile]
    @State private var draft: ProfileDraft?

    var body: some View {
        Form {
            if let profile = profiles.first {
                let binding = Binding(get: { draft ?? ProfileDraft(profile: profile) }, set: { draft = $0 })
                ProfileFormView(draft: binding, clock: model.clock)
                Section {
                    Button("Enregistrer") {
                        binding.wrappedValue.apply(to: profile)
                        dismiss()
                    }
                    .disabled(
                        binding.wrappedValue.input(clock: model.clock) == nil
                            || binding.wrappedValue.validationMessage(clock: model.clock) != nil
                    )
                }
            }
        }
        .themedList()
        .navigationTitle("Mon profil")
        .keyboardDoneButton()
    }
}
