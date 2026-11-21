import ShreddishCore
import SwiftData
import SwiftUI

/// Accord avant le premier envoi à OpenAI (spec 017, FR-1714).
struct AIConsentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("""
                        Pour composer tes menus et rédiger les recettes, Shreddish envoie une partie de tes données à \
                        OpenAI. OpenAI ne les conserve pas au-delà de la réponse et ne s'en sert pas pour entraîner \
                        ses modèles.
                        """)
                }
                ThemedSection("Envoyé") {
                    ForEach(AIConsent.sentData, id: \.self) { Label($0, systemImage: "arrow.up.circle") }
                }
                ThemedSection("Jamais envoyé") {
                    ForEach(AIConsent.neverSent, id: \.self) { Label($0, systemImage: "lock") }
                }
                Section {
                    Button("J'accepte") {
                        AIConsent.grant(at: model.clock.now)
                        dismiss()
                    }
                    .buttonStyle(PillButtonStyle())
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("acceptAIConsent")
                    Button("Pas maintenant", role: .cancel) { dismiss() }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } footer: {
                    ListFooter {
                        Text("""
                            Sans accord, l'app fonctionne sauf la génération des menus et des recettes. Retirable dans \
                            Réglages → Confidentialité.
                            """)
                    }
                }
            }
            .themedList()
            .navigationTitle("Tes données et l'IA")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Confidentialité, conditions, export et retrait du consentement (spec 017, FR-1714).
struct PrivacySettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var consent = AIConsent.isGranted
    @State private var exportURL: URL?

    var body: some View {
        List {
            Section {
                NavigationLink("Politique de confidentialité") { LegalText(title: "Confidentialité", text: LegalTexts.privacy) }
                NavigationLink("Conditions d'utilisation") { LegalText(title: "Conditions", text: LegalTexts.terms) }
            }
            Section {
                Toggle("Envoi à OpenAI autorisé", isOn: $consent)
                    .onChange(of: consent) { _, on in if on { AIConsent.grant() } else { AIConsent.revoke() } }
                    .accessibilityIdentifier("aiConsentToggle")
            } footer: {
                ListFooter {
                    Text("Désactivé : plus aucun envoi, les menus et recettes déjà créés restent.")
                }
            }
            Section {
                if let exportURL {
                    ShareLink("Partager l'export", item: exportURL)
                } else {
                    Button("Exporter mes données", systemImage: "square.and.arrow.up") {
                        exportURL = try? DataExport.write(from: context)
                    }
                    .accessibilityIdentifier("exportData")
                }
            } footer: {
                ListFooter {
                    Text("""
                        Fichier JSON lisible : profil, préférences, plannings, journal, pesées, mensurations, \
                        recettes. Les photos restent sur ton iPhone.
                        """)
                }
            }
        }
        .themedList()
        .navigationTitle("Confidentialité")
    }
}

private struct LegalText: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(Theme.text(.body))
                .foregroundStyle(Theme.ink)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .paperBackground()
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Export RGPD : toutes les données de l'utilisateur dans un fichier JSON.
enum DataExport {
    @MainActor
    static func write(from context: ModelContext) throws -> URL {
        func fetch<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        let plans = fetch(WeeklyPlan.self).sorted { $0.startDayKey < $1.startDayKey }
        let export: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: .now),
            "profile": fetch(Profile.self).map { profile in
                [
                    "sex": profile.sexRaw, "birthDate": ISO8601DateFormatter().string(from: profile.birthDate),
                    "heightCm": profile.heightCm, "weightKg": profile.weightKg, "goal": profile.goalRaw,
                ] as [String: Any]
            },
            "preferences": fetch(Preferences.self).map { prefs in
                [
                    "mealsPerDay": prefs.mealsPerDay, "weeklyBudget": prefs.weeklyBudget, "allergies": prefs.allergyList,
                    "dislikedFoods": prefs.excludedFoods, "likedFoods": prefs.likedFoods, "diets": prefs.diets.map(\.rawValue),
                ] as [String: Any]
            },
            "plans": plans.map { plan in
                [
                    "startDay": plan.startDayKey,
                    "days": plan.sortedDays.map { day in
                        [
                            "day": day.dayKey,
                            "meals": day.sortedMeals.map { ["name": $0.name, "kcal": $0.kcal, "status": $0.statusRaw] },
                            "extras": day.sortedExtras.map { ["name": $0.name, "kcal": $0.kcal] },
                        ] as [String: Any]
                    },
                ] as [String: Any]
            },
            "weights": fetch(WeightEntry.self).map { ["day": $0.dayKey, "kg": $0.weightKg] },
            "measurements": fetch(BodyMeasurement.self).map { entry in
                ["day": entry.dayKey, "waistCm": entry.waistCm as Any, "hipsCm": entry.hipsCm as Any]
            },
            "recipes": fetch(SavedRecipe.self).map { ["name": $0.name, "steps": $0.steps] },
            "household": fetch(HouseholdMember.self).map { member in
                [
                    "name": member.name, "portion": member.portion,
                    "weights": fetch(MemberWeight.self).filter { $0.memberID == member.id }
                        .map { ["day": $0.dayKey, "kg": $0.weightKg] },
                ] as [String: Any]
            },
            "receipts": fetch(ShoppingReceipt.self).map { receipt in
                ["startDay": plans.first { $0.id == receipt.planID }?.startDayKey as Any, "paidEUR": receipt.amountEUR]
            },
            "quickFoods": fetch(QuickFood.self).map { ["name": $0.name, "grams": $0.lastGrams] },
        ]
        let data = try JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])
        let url = FileManager.default.temporaryDirectory.appending(path: "shreddish-export.json")
        try data.write(to: url)
        return url
    }
}

/// Textes juridiques. À faire relire par un juriste avant publication.
enum LegalTexts {
    static let privacy = String(localized: """
    Shreddish garde tes données sur ton iPhone. Aucun compte, aucune publicité, aucun traceur.

    Données envoyées à OpenAI, seulement après ton accord : tes cibles nutritionnelles, ton objectif, tes préférences \
    alimentaires et les ingrédients des repas à rédiger. Jamais ton âge, ton poids, ta taille, ton journal, tes photos \
    ni tes données de santé. OpenAI ne conserve pas ces requêtes (option store désactivée).

    Code-barres : seul le code scanné est envoyé à Open Food Facts pour retrouver le produit.

    Apple Santé : désactivé par défaut. Une fois activé, les échanges restent entre Shreddish et Santé, sur ton iPhone.

    Tes droits (RGPD) : exporter tes données (Réglages → Confidentialité), les supprimer (Réglages → Supprimer toutes \
    mes données), retirer ton accord à l'envoi à OpenAI à tout moment.
    """)

    static let terms = String(localized: """
    Shreddish aide à planifier des repas selon des cibles calculées par des formules reconnues (Mifflin-St Jeor). \
    Ce n'est ni un dispositif médical ni un avis médical.

    Ne l'utilise pas si tu es mineur, enceinte ou allaitante, ou en cas de trouble du comportement alimentaire, \
    de diabète, de maladie rénale ou de tout traitement qui dépend de ton alimentation, sans l'accord de ton médecin.

    Les valeurs nutritionnelles (table Ciqual, Open Food Facts) et les prix sont des estimations. Vérifie les \
    étiquettes en cas d'allergie : l'IA peut se tromper malgré les contrôles.

    L'abonnement se gère dans les réglages de ton identifiant Apple ; l'essai gratuit se convertit sauf résiliation \
    au moins 24 heures avant sa fin.
    """)
}
