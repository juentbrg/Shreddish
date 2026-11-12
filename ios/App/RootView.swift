import ShreddishCore
import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query var profiles: [Profile]

    private var profile: Profile? {
        profiles.first { $0.disclaimerAcceptedAt != nil }
    }

    var body: some View {
        if profile == nil {
            OnboardingView()
        } else {
            tabs
                .task {
                    PlanStore.cleanUpStoredData(in: context)
                    model.calibrateIfDue(context: context)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.calibrateIfDue(context: context) }
                }
        }
    }

    private var tabs: some View {
        @Bindable var model = model
        return TabView(selection: $model.selectedTab) {
            Tab("Semaine", systemImage: "fork.knife", value: AppModel.Tab.week) {
                WeekView()
            }
            Tab("Journal", systemImage: "checklist", value: AppModel.Tab.journal) {
                JournalView()
            }
            Tab("Courses", systemImage: "cart", value: AppModel.Tab.shopping) {
                ShoppingListView()
            }
            Tab("Poids", systemImage: "scalemass", value: AppModel.Tab.weight) {
                WeightView()
            }
            Tab("Cibles", systemImage: "target", value: AppModel.Tab.targets) {
                TargetsView()
            }
        }
        .overlay {
            if let message = model.busyMessage {
                BusyOverlay(message: message)
            }
        }
        .alert(
            "Génération impossible",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct BusyOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Ça peut prendre jusqu'à une minute.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("busy")
    }
}
