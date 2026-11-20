import ShreddishCore
import SwiftData
import SwiftUI

/// Foyer (spec 017, FR-1704) : mêmes plats pour tous, une portion par personne, courses pour tout le foyer.
struct HouseholdView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \HouseholdMember.createdAt) var members: [HouseholdMember]
    @Query var profiles: [Profile]
    @State private var editing: HouseholdMember?
    @State private var adding = false

    private var mainKcal: Int { profiles.first?.targets(clock: model.clock)?.targetKcal ?? 0 }

    var body: some View {
        List {
            Section {
                LabeledContent("Toi", value: "1 portion")
                ForEach(members) { member in
                    Button {
                        editing = member
                    } label: {
                        LabeledContent(member.name.isEmpty ? String(localized: "Sans nom") : member.name,
                            value: Format.portion(member.portion))
                            .foregroundStyle(Theme.ink)
                    }
                    .accessibilityIdentifier("member-\(member.name)")
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(members[index]) }
                    saveAndRebuild()
                }
                Button("Ajouter une personne", systemImage: "person.badge.plus") { adding = true }
                    .accessibilityIdentifier("addMember")
            } header: {
                ListHeader {
                    Text("Personnes")
                }
            } footer: {
                ListFooter {
                    Text("""
                        Mêmes plats pour tout le monde. Courses et budget pour \
                        \(Format.portion(Household.portions(members))) au total ; tes macros restent calculées pour ta \
                        portion.
                        """)
                }
            }
        }
        .themedList()
        .navigationTitle("Mon foyer")
        .sheet(isPresented: $adding) {
            MemberEditView(member: nil, mainKcal: mainKcal) { member in
                context.insert(member)
                saveAndRebuild()
            }
        }
        .sheet(item: $editing) { member in
            MemberEditView(member: member, mainKcal: mainKcal) { _ in saveAndRebuild() }
        }
        .onAppear {
            for member in members { member.refreshPortion(mainKcal: mainKcal, clock: model.clock) }
        }
    }

    private func saveAndRebuild() {
        try? context.save()
        PlanStore.rebuildActiveShoppingLists(in: context)
    }
}

/// Ajout ou modification d'une personne : portion choisie, ou calculée depuis son profil.
private struct MemberEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let member: HouseholdMember?
    let mainKcal: Int
    let onSave: (HouseholdMember) -> Void

    @State private var name = ""
    @State private var portion = 1.0
    @State private var useProfile = false
    @State private var sex = Sex.female
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    @State private var height = ""
    @State private var weight = ""
    @State private var activity = ActivityLevel.moderate
    @State private var goal = Goal.recomp

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Prénom", text: $name)
                        .accessibilityIdentifier("memberName")
                    Toggle("Calculer sa portion", isOn: $useProfile)
                        .accessibilityIdentifier("memberUseProfile")
                }
                if useProfile {
                    profileSection
                } else {
                    Section {
                        Stepper(
                            Format.portion(portion), value: $portion, in: HouseholdMember.portionRange, step: 0.25
                        )
                        .accessibilityIdentifier("memberPortion")
                    } footer: {
                        ListFooter {
                            Text("1 = même assiette que toi, 0,5 = enfant ou petit appétit.")
                        }
                    }
                }
            }
            .themedList()
            .navigationTitle(member == nil ? String(localized: "Nouvelle personne") : String(localized: "Modifier"))
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (useProfile && draft == nil))
                        .accessibilityIdentifier("saveMember")
                }
            }
            .onAppear(perform: load)
        }
    }

    private var profileSection: some View {
        Section {
            Picker("Genre", selection: $sex) {
                Text("Femme").tag(Sex.female)
                Text("Homme").tag(Sex.male)
            }
            DatePicker("Naissance", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
            LabeledContent("Taille (cm)") {
                TextField("170", text: $height).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("Poids (kg)") {
                TextField("65", text: $weight).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Picker("Activité", selection: $activity) {
                ForEach(ActivityLevel.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("Objectif", selection: $goal) {
                ForEach(Goal.allCases, id: \.self) { Text($0.label).tag($0) }
            }
        } footer: {
            ListFooter {
                if let draft, let targets = draft.targets(clock: model.clock) {
                    Text("\(Format.kcal(Double(targets.targetKcal))) par jour : \(Format.portion(draftPortion(draft))).")
                } else {
                    Text("Taille et poids pour calculer sa portion.")
                }
            }
        }
    }

    /// Membre temporaire pour le calcul, nil si le profil est incomplet ou invalide.
    private var draft: HouseholdMember? {
        guard let heightCm = Format.parse(height), let weightKg = Format.parse(weight) else { return nil }
        let draft = HouseholdMember(name: name)
        fill(draft, heightCm: heightCm, weightKg: weightKg)
        return draft.targets(clock: model.clock) == nil ? nil : draft
    }

    private func draftPortion(_ draft: HouseholdMember) -> Double {
        draft.refreshPortion(mainKcal: mainKcal, clock: model.clock)
        return draft.portion
    }

    private func fill(_ target: HouseholdMember, heightCm: Double?, weightKg: Double?) {
        target.sexRaw = sex.rawValue
        target.birthDate = birthDate
        target.heightCm = heightCm
        target.weightKg = weightKg
        target.activityRaw = activity.rawValue
        target.goalRaw = goal.rawValue
    }

    private func load() {
        guard let member else { return }
        name = member.name
        portion = member.portion
        useProfile = member.hasProfile
        if let raw = member.sexRaw, let value = Sex(rawValue: raw) { sex = value }
        if let date = member.birthDate { birthDate = date }
        height = member.heightCm.map { Format.number($0, digits: 0) } ?? ""
        weight = member.weightKg.map { Format.number($0) } ?? ""
        if let raw = member.activityRaw, let value = ActivityLevel(rawValue: raw) { activity = value }
        if let raw = member.goalRaw, let value = Goal(rawValue: raw) { goal = value }
    }

    private func save() {
        let target = member ?? HouseholdMember(name: "", createdAt: model.clock.now)
        target.name = name.trimmingCharacters(in: .whitespaces)
        if useProfile {
            fill(target, heightCm: Format.parse(height), weightKg: Format.parse(weight))
            target.refreshPortion(mainKcal: mainKcal, clock: model.clock)
        } else {
            target.sexRaw = nil
            target.heightCm = nil
            target.weightKg = nil
            target.portion = portion
        }
        onSave(target)
        dismiss()
    }
}
