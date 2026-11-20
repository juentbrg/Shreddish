import Foundation
import Testing
@testable import Shreddish

/// Abonnement (spec 017, FR-1715) : première semaine offerte, puis abonnement exigé en Release.
@MainActor
struct SubscriptionTests {
    let defaults = UserDefaults(suiteName: "subscription-tests-\(UUID().uuidString)")!

    @Test func firstWeekIsFreeThenPaywall() {
        let store = SubscriptionStore(enforced: true, defaults: defaults)
        #expect(store.hasAccess)
        store.freeWeekUsed = true
        #expect(!store.hasAccess)
    }

    @Test func notEnforcedKeepsAccess() {
        let store = SubscriptionStore(enforced: false, defaults: defaults)
        store.freeWeekUsed = true
        #expect(store.hasAccess)
    }
}
