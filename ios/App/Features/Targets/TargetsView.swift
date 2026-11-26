import ShreddishCore
import SwiftData
import SwiftUI

/// Profil : pesée du jour, cibles kcal et macros, détail du calcul (US1, US6, FR-002 à FR-005).
struct TargetsView: View {
    @Environment(AppModel.self) private var model
    @Query var profiles: [Profile]
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
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
            .navigationDestination(for: WeighInRoute.self) { _ in ProfileEditView() }
            .onAppear(perform: openDeepLink)
            .onChange(of: model.deepLink) { openDeepLink() }
        }
    }

    /// Rappel de pesée touché : « Modifier mon profil », où se trouve la pesée.
    private func openDeepLink() {
        guard model.deepLink == .weighIn else { return }
        model.deepLink = nil
        path = NavigationPath([WeighInRoute()])
    }

    private func content(profile: Profile, targets: NutritionTargets) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TargetsHeroCard(goal: profile.goal, targets: targets, adjustment: targets.breakdown.calorieAdjustment)
                WeightSummaryCard(profile: profile) { path.append(WeighInRoute()) }
                if let message = model.calibrationMessage {
                    Label(message, systemImage: "scalemass.fill")
                        .font(Theme.text(.subheadline))
                        .foregroundStyle(Theme.success)
                        .card()
                        .accessibilityIdentifier("calibrationMessage")
                }
                ForEach(targets.warnings, id: \.self) { warning in
                    Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.text(.subheadline))
                        .foregroundStyle(Theme.tomatoInk)
                        .card()
                }
                tiles(profile)
                if profile.dailyActivity == nil {
                    NavigationLink {
                        ProfileEditView()
                    } label: {
                        Label(
                            String(localized: "Précise ton activité (séances, intensité, pas) pour une dépense plus juste."),
                            systemImage: "figure.strengthtraining.traditional"
                        )
                        .font(Theme.text(.subheadline))
                        .foregroundStyle(Theme.ink)
                        .card()
                    }
                    .buttonStyle(.plain)
                }
                CalculationLadder(breakdown: targets.breakdown, targets: targets, profile: profile)
                Text("Estimations, pas un avis médical.")
                    .font(Theme.text(.footnote))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func tiles(_ profile: Profile) -> some View {
        let age = profile.age(on: model.clock.now, calendar: model.clock.calendar)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            NavigationLink { ProfileEditView() } label: {
                ProfileTile(
                    title: "Modifier mon profil", detail: "\(Format.number(profile.heightCm, digits: 0)) cm · \(age) ans",
                    symbol: "person", colors: (Theme.line, Theme.ink)
                )
            }
            .accessibilityIdentifier("editProfile")
            NavigationLink { BodyProgressView() } label: {
                ProfileTile(
                    title: "Mes progrès", detail: String(localized: "Pesées, photos, mesures"),
                    symbol: "chart.line.downtrend.xyaxis", colors: (Theme.successSoft, Theme.success)
                )
            }
            .accessibilityIdentifier("bodyProgress")
            NavigationLink { MacroSettingsView() } label: {
                ProfileTile(
                    title: "Ajuster les macros", detail: String(localized: "Protéines, lipides, glucides"),
                    symbol: "slider.horizontal.3", colors: (Theme.carbs.soft, Theme.carbs.ink)
                )
            }
            NavigationLink { CalibrationView() } label: {
                ProfileTile(
                    title: "Calibration",
                    detail: profile.isAutoCalibrationOn
                        ? String(localized: "Auto, par les pesées") : String(localized: "Manuelle"),
                    symbol: "scope", colors: (Theme.fat.soft, Theme.fat.ink)
                )
            }
            .accessibilityIdentifier("calibration")
        }
        .buttonStyle(.plain)
    }
}

extension TargetWarning {
    var message: String {
        switch self {
        case .floorApplied: String(localized: "Cible ramenée au plancher de sécurité : descendre plus bas n'est pas conseillé.")
        case .underweightNoDeficit:
            "IMC sous 18,5 : pas de déficit calorique, cible à l'entretien. Parles-en à un médecin avant une sèche."
        case .fatReduced: String(localized: "Lipides abaissés (minimum 0,6 g/kg) pour garder des glucides.")
        case .carbsAtZero: String(localized: "Protéines et lipides couvrent déjà toute la cible : glucides à 0. Revois tes réglages.")
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

/// Carte de l'objectif : kcal par jour et macros (même style que la carte du jour).
struct TargetsHeroCard: View {
    let goal: Goal
    let targets: NutritionTargets
    /// Ajustement de l'objectif (−20 % en sèche) ; `nil` : pas de badge.
    var adjustment: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("\(goal.label) · cible par jour")
                        .font(Theme.text(.footnote, .medium))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    if let adjustment, abs(adjustment) > 0.001 {
                        Text(Format.percent(adjustment, signed: true))
                            .font(Theme.text(.caption, .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.line, in: Capsule())
                    }
                }
                Text(Format.kcal(Double(targets.targetKcal)))
                    .font(Theme.display(38, .heavy, relativeTo: .largeTitle))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("targetKcal")
            }
            MacroSplitBar(
                proteinG: Double(targets.proteinG), carbsG: Double(targets.carbsG), fatG: Double(targets.fatG)
            )
            HStack(spacing: 8) {
                MacroTile(title: "Protéines", value: Double(targets.proteinG), target: nil, palette: Theme.protein)
                MacroTile(title: "Glucides", value: Double(targets.carbsG), target: nil, palette: Theme.carbs)
                MacroTile(title: "Lipides", value: Double(targets.fatG), target: nil, palette: Theme.fat)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
