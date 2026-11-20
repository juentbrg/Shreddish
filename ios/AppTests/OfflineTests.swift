import Foundation
import ShreddishCore
import Testing
@testable import Shreddish

/// Hors ligne (spec 017, FR-1702) : action IA mise en attente puis relancée.
@MainActor
struct OfflineTests {
    @Test func offlineActionIsKeptAndResumed() async {
        AIConsent.grant()
        let model = AppModel(clock: SystemClock(), keyStore: InMemoryKeyStore(key: "sk"), transport: UITestAITransport(), isUITest: true)
        var calls = 0
        let action: () async throws(AIError) -> [ValidationIssue] = {
            calls += 1
            if calls == 1 { throw AIError.offline }
            return []
        }
        await model.run("Préparation de ta semaine…", action)
        #expect(model.errorMessage == nil)
        #expect(model.pending != nil)
        #expect(model.warningMessage?.contains("Hors ligne") == true)
        await model.resumePending()
        #expect(calls == 2)
        #expect(model.pending == nil)
    }

    @Test func otherErrorsAreShown() async {
        AIConsent.grant()
        let model = AppModel(clock: SystemClock(), keyStore: InMemoryKeyStore(key: "sk"), transport: UITestAITransport(), isUITest: true)
        await model.run("Test") { () async throws(AIError) -> [ValidationIssue] in throw AIError.rateLimited }
        #expect(model.errorMessage != nil)
        #expect(model.pending == nil)
    }
}
