import ShreddishCore
import SwiftUI

/// Saisie du profil, partagée entre onboarding et édition.
struct ProfileDraft: Equatable {
    var sex: Sex = .male
    var birthDate: Date
    var height = ""
    var weight = ""
    /// Ancien niveau unique, conservé pour les profils d'avant la spec 002 (non affiché).
    var activity: ActivityLevel = .moderate
    var dailyActivity: DailyActivity = .sedentary
    var training: TrainingLoad = .defaultLoad
    var goal: Goal = .cut

    /// Défaut : 30 ans à la date du jour.
    init(clock: any AppClock) {
        birthDate = clock.calendar.date(byAdding: .year, value: -30, to: clock.now) ?? clock.now
    }

    init(profile: Profile) {
        sex = profile.sex
        birthDate = profile.birthDate
        height = Format.number(profile.heightCm)
        weight = Format.number(profile.weightKg)
        activity = profile.activity
        dailyActivity = profile.dailyActivity ?? .sedentary
        training = profile.training ?? .defaultLoad
        goal = profile.goal
    }

    func input(clock: any AppClock) -> ProfileInput? {
        guard let height = Format.parse(height), let weight = Format.parse(weight) else { return nil }
        let age = clock.calendar.dateComponents([.year], from: birthDate, to: clock.now).year ?? 0
        return ProfileInput(
            sex: sex, age: age, heightCm: height, weightKg: weight, activity: activity, goal: goal,
            dailyActivity: dailyActivity, training: training
        )
    }

    /// Message d'erreur de saisie, `nil` si le profil est valide.
    func validationMessage(clock: any AppClock) -> String? {
        guard let input = input(clock: clock) else {
            return height.isEmpty || weight.isEmpty ? nil : "Taille et poids doivent être des nombres."
        }
        do {
            try NutritionCalculator.validate(input)
            return nil
        } catch {
            return error.message
        }
    }

    func apply(to profile: Profile) {
        guard let height = Format.parse(height), let weight = Format.parse(weight) else { return }
        profile.sex = sex
        profile.birthDate = birthDate
        profile.heightCm = height
        profile.weightKg = weight
        profile.activity = activity
        profile.dailyActivity = dailyActivity
        profile.training = training
        profile.goal = goal
    }
}

extension ProfileValidationError {
    var message: String {
        switch self {
        case .ageOutOfRange: "Âge accepté : de 16 à 90 ans."
        case .heightOutOfRange: "Taille acceptée : de 120 à 230 cm."
        case .weightOutOfRange: "Poids accepté : de 35 à 250 kg."
        case .overrideOutOfRange(.proteinPerKg): "Protéines : de 1,2 à 3 g par kg."
        case .overrideOutOfRange(.fatPerKg): "Lipides : de 0,6 à 1,5 g par kg."
        case .overrideOutOfRange(.calorieAdjustment): "Ajustement calorique : de −30 % à +20 %."
        case .trainingOutOfRange: "Entraînement : de 0 à 14 séances, de 15 à 240 minutes."
        }
    }
}

struct ProfileFormView: View {
    @Binding var draft: ProfileDraft
    let clock: any AppClock

    var body: some View {
        Section("Toi") {
            Picker("Genre", selection: $draft.sex) {
                ForEach(Sex.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            DatePicker(
                "Date de naissance", selection: $draft.birthDate,
                in: ...clock.now, displayedComponents: .date
            )
            .environment(\.locale, Format.locale)
            LabeledContent("Taille (cm)") {
                TextField("180", text: $draft.height)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("height")
            }
            LabeledContent("Poids (kg)") {
                TextField("80", text: $draft.weight)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("weight")
            }
        }
        Section {
            Picker("Au quotidien", selection: $draft.dailyActivity) {
                ForEach(DailyActivity.allCases, id: \.self) { level in
                    VStack(alignment: .leading) {
                        Text(level.label)
                        Text(level.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(level)
                }
            }
            .pickerStyle(.navigationLink)
            .accessibilityIdentifier("dailyActivity")
        } header: {
            Text("Activité hors sport")
        }
        TrainingSection(training: $draft.training, weightKg: Format.parse(draft.weight))
        Section("Objectif") {
            Picker("Objectif", selection: $draft.goal) {
                ForEach(Goal.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        if let message = draft.validationMessage(clock: clock) {
            Section {
                Label(message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("validationError")
            }
        }
    }
}

/// Séances par semaine, durée moyenne, intensité (spec 002, FR-102).
struct TrainingSection: View {
    @Binding var training: TrainingLoad
    let weightKg: Double?

    var body: some View {
        Section {
            Stepper(
                "\(training.sessionsPerWeek) séance\(training.sessionsPerWeek > 1 ? "s" : "") par semaine",
                value: $training.sessionsPerWeek, in: TrainingLoad.sessionsRange
            )
            .accessibilityIdentifier("sessions")
            if training.sessionsPerWeek > 0 {
                Stepper(
                    "\(training.minutesPerSession) min par séance",
                    value: $training.minutesPerSession, in: TrainingLoad.minutesRange, step: 15
                )
                .accessibilityIdentifier("sessionMinutes")
                Picker("Intensité", selection: $training.intensity) {
                    ForEach(TrainingIntensity.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("intensity")
            }
        } header: {
            Text("Entraînement")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if training.sessionsPerWeek > 0 {
                    Text(training.intensity.detail)
                }
                if let weightKg, training.sessionsPerWeek > 0 {
                    Text("≈ \(Format.kcal(training.kcalPerSession(weightKg: weightKg))) par séance.")
                }
            }
        }
    }
}
