import Foundation
import Observation
import StoreKit

/// Abonnement (spec 017, FR-1715) : mensuel 9,99 €, annuel 69,99 €, essai de 7 jours.
/// La première semaine est offerte avant toute demande de paiement (FR-1717). En build Debug, accès complet.
@MainActor
@Observable
final class SubscriptionStore {
    static let productIDs = ["app.shreddish.yearly", "app.shreddish.monthly"]
    static let freeWeekKey = "freeWeekUsed"

    private(set) var products: [Product] = []
    private(set) var isSubscribed = false
    private(set) var purchaseError: String?
    private let defaults: UserDefaults
    /// Paiement exigé (Release) ; en Debug et en test, l'app reste utilisable sans abonnement.
    let isEnforced: Bool
    private var updates: Task<Void, Never>?

    init(enforced: Bool, defaults: UserDefaults = .standard) {
        isEnforced = enforced
        self.defaults = defaults
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case let .verified(transaction) = update { await transaction.finish() }
                await self?.refresh()
            }
        }
    }

    /// Première semaine générée : la suivante demandera l'abonnement.
    var freeWeekUsed: Bool {
        get { defaults.bool(forKey: Self.freeWeekKey) }
        set { defaults.set(newValue, forKey: Self.freeWeekKey) }
    }

    /// Génération autorisée : abonné, première semaine, ou paiement non exigé.
    var hasAccess: Bool { !isEnforced || isSubscribed || !freeWeekUsed }

    func load() async {
        if products.isEmpty {
            products = ((try? await Product.products(for: Self.productIDs)) ?? [])
                .sorted { Self.productIDs.firstIndex(of: $0.id) ?? 0 < Self.productIDs.firstIndex(of: $1.id) ?? 0 }
        }
        await refresh()
    }

    func refresh() async {
        var active = false
        for await entitlement in Transaction.currentEntitlements {
            if case let .verified(transaction) = entitlement, transaction.revocationDate == nil,
               Self.productIDs.contains(transaction.productID) {
                active = true
            }
        }
        isSubscribed = active
    }

    func purchase(_ product: Product) async {
        purchaseError = nil
        do {
            switch try await product.purchase() {
            case let .success(.verified(transaction)):
                await transaction.finish()
                await refresh()
            case .success(.unverified):
                purchaseError = String(localized: "Achat non vérifié par Apple.")
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = String(localized: "Achat impossible : réessaie plus tard.")
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }
}
