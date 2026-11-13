import ShreddishCore
import SwiftData
import SwiftUI

/// Premier lancement : avertissement puis profil (US1, FR-005).
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var accepted = false
    @State private var draft: ProfileDraft?

    var body: some View {
        NavigationStack {
            if accepted {
                profileStep
            } else {
                DisclaimerView { accepted = true }
            }
        }
    }

    private var profileStep: some View {
        let binding = Binding(
            get: { draft ?? ProfileDraft(clock: model.clock) },
            set: { draft = $0 }
        )
        let current = binding.wrappedValue
        let isValid = current.input(clock: model.clock) != nil && current.validationMessage(clock: model.clock) == nil
        return Form {
            ProfileFormView(draft: binding, clock: model.clock)
            Section {
                Button("Calculer mes besoins") { save(current) }
                    .frame(maxWidth: .infinity)
                    .bold()
                    .disabled(!isValid)
                    .accessibilityIdentifier("computeTargets")
            }
        }
        .themedList()
        .navigationTitle("Ton profil")
        .keyboardDoneButton()
    }

    private func save(_ draft: ProfileDraft) {
        guard let input = draft.input(clock: model.clock) else { return }
        let profile = Profile(
            sex: input.sex, birthDate: draft.birthDate, heightCm: input.heightCm, weightKg: input.weightKg,
            activity: input.activity, goal: input.goal
        )
        profile.dailyActivity = input.dailyActivity
        profile.training = input.training
        profile.disclaimerAcceptedAt = model.clock.now
        context.insert(profile)
        if (try? context.fetchCount(FetchDescriptor<Preferences>())) ?? 0 == 0 {
            context.insert(Preferences())
        }
        let day = model.clock.today
        context.insert(WeightEntry(day: day, weightKg: input.weightKg, recordedAt: model.clock.now))
        try? context.save()
        model.selectedTab = .targets
    }
}

struct DisclaimerView: View {
    let onAccept: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Bienvenue sur Shreddish")
                    .font(.largeTitle.bold())
                Text("Repas simples, pas chers et rapides, calés sur ton objectif.")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 12) {
                    Label("Pas un avis médical.", systemImage: "stethoscope")
                    Label("Cibles, valeurs et prix : des estimations.", systemImage: "function")
                    Label("Pathologie, grossesse, doute : vois un professionnel de santé.", systemImage: "heart.text.square")
                }
                .font(.body)
                Button(action: onAccept) {
                    Text("J'ai compris, continuer")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("acceptDisclaimer")
            }
            .padding(24)
        }
    }
}
