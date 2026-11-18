import ShreddishCore
import SwiftData
import SwiftUI

/// Profil : pesée du jour, cibles kcal et macros, détail du calcul (US1, US6, FR-002 à FR-005).
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
            .navigationTitle("Mon profil")
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
                TargetsHeroCard(goal: profile.goal, targets: targets)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
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
            if let message = model.calibrationMessage {
                Section {
                    Label(message, systemImage: "scalemass.fill")
                        .foregroundStyle(Theme.green)
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
                            .foregroundStyle(Theme.tomato)
                    }
                }
            }
            breakdownSection(targets.breakdown, targets: targets, profile: profile)
            Section {
                Text("Estimations, pas un avis médical.")
                    .font(Theme.text(.footnote))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func breakdownSection(_ breakdown: CalculationBreakdown, targets: NutritionTargets, profile: Profile) -> some View {
        ThemedSection("Détail du calcul") {
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
                .font(Theme.text(.footnote))
                .foregroundStyle(Theme.muted)
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
    @Query(sort: \WeightEntry.dayKey) var entries: [WeightEntry]
    @State private var draft: ProfileDraft?

    var body: some View {
        Form {
            if let profile = profiles.first {
                let binding = Binding(get: { draft ?? ProfileDraft(profile: profile) }, set: { draft = $0 })
                WeightEntrySection()
                WeightTrendSection(entries: entries, goal: profile.goal)
                Section {
                    NavigationLink {
                        WeightView()
                    } label: {
                        Label("Courbe et historique des pesées", systemImage: "chart.xyaxis.line")
                    }
                    .accessibilityIdentifier("weightHistory")
                }
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
        .navigationTitle("Modifier mon profil")
        .keyboardDoneButton()
    }
}

/// Carte verte de l'objectif : kcal par jour et macros (même style que la carte du jour).
struct TargetsHeroCard: View {
    let goal: Goal
    let targets: NutritionTargets

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(goal.label) · par jour")
                    .font(Theme.text(.footnote))
                    .opacity(0.85)
                Text(Format.kcal(Double(targets.targetKcal)))
                    .font(Theme.display(38, .heavy, relativeTo: .largeTitle))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityIdentifier("targetKcal")
            }
            HStack(spacing: 8) {
                MacroTile(title: "Protéines", value: Double(targets.proteinG), target: nil)
                MacroTile(title: "Glucides", value: Double(targets.carbsG), target: nil)
                MacroTile(title: "Lipides", value: Double(targets.fatG), target: nil)
            }
        }
        .foregroundStyle(Theme.onGreen)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.green, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
