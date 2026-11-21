import SwiftUI

/// Apple Watch (spec 017, FR-1711) : repas du jour, mangé / sauté, pesée rapide. Données de l'iPhone.
@main
struct ShreddishWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            TodayView()
                .environment(store)
        }
    }
}
