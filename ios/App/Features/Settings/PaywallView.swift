import StoreKit
import SwiftUI

/// Abonnement (spec 017, FR-1715) : avantages, deux formules, essai de 7 jours, restauration.
struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String = SubscriptionStore.productIDs[0]
    @State private var buying = false

    private let benefits = [
        ("fork.knife", String(localized: "Une semaine de menus calés sur tes cibles, chaque semaine")),
        ("cart", String(localized: "Courses au prix réel, paquets entiers, sans gaspillage")),
        ("person.2", String(localized: "Tout le foyer avec un seul abonnement")),
        ("chart.line.downtrend.xyaxis", String(localized: "Calibration sur tes pesées, suivi de tes progrès")),
    ]

    var body: some View {
        let store = model.subscriptions
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Continue ta sèche avec Shreddish")
                        .font(Theme.display(28, .heavy, relativeTo: .title))
                        .foregroundStyle(Theme.ink)
                    ForEach(benefits, id: \.1) { icon, text in
                        Label(text, systemImage: icon).font(Theme.text(.body))
                    }
                    ForEach(store.products, id: \.id) { product in
                        planCard(product)
                    }
                    if store.products.isEmpty {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    Button {
                        guard let product = store.products.first(where: { $0.id == selected }) else { return }
                        buying = true
                        Task {
                            await store.purchase(product)
                            buying = false
                            if store.isSubscribed { dismiss() }
                        }
                    } label: {
                        Text(buying ? "…" : String(localized: "Essayer 7 jours gratuitement"))
                    }
                    .buttonStyle(PillButtonStyle())
                    .disabled(store.products.isEmpty || buying)
                    .accessibilityIdentifier("startTrial")
                    if let error = store.purchaseError {
                        Text(error).font(Theme.text(.footnote)).foregroundStyle(Theme.tomato)
                    }
                    Text("""
                        Sans engagement : résilie à tout moment dans les réglages de ton identifiant Apple, au moins \
                        24 h avant la fin de l'essai pour ne rien payer.
                        """)
                        .font(Theme.text(.caption))
                        .foregroundStyle(Theme.muted)
                    HStack {
                        Button("Restaurer mes achats") { Task { await store.restore() } }
                        Spacer()
                        NavigationLink("Conditions") { PrivacySettingsView() }
                    }
                    .font(Theme.text(.footnote, .semibold))
                }
                .padding(20)
            }
            .paperBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Plus tard") { dismiss() } }
            }
            .task { await store.load() }
        }
    }

    private func planCard(_ product: Product) -> some View {
        let isSelected = selected == product.id
        let yearly = product.subscription?.subscriptionPeriod.unit == .year
        return Button {
            selected = product.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName).font(Theme.text(.headline, .semibold))
                    Text(yearly
                        ? String(localized: "\(product.displayPrice) par an · 7 jours offerts")
                        : String(localized: "\(product.displayPrice) par mois · 7 jours offerts"))
                        .font(Theme.text(.subheadline))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                if yearly {
                    Text("−40 %").font(Theme.text(.caption, .bold)).padding(6).background(Theme.wheat, in: Capsule())
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.green : Theme.muted)
            }
            .foregroundStyle(Theme.ink)
            .card()
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(isSelected ? Theme.green : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan-\(product.id)")
    }
}
