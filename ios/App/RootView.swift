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
                    model.recipes.fillMissing(in: context)
                    model.calibrateIfDue(context: context)
                    await model.notifications.requestAuthorizationIfNeeded()
                    await model.notifications.reschedule()
                    await model.health.sync(container: context.container, clock: model.clock)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.calibrateIfDue(context: context)
                        Task { await model.health.sync(container: context.container, clock: model.clock) }
                    }
                    // Rappels recalculés à l'ouverture et à la sortie : plannings, coches et pesées à jour.
                    if phase != .inactive {
                        Task { await model.notifications.reschedule() }
                        model.watch.push()
                    }
                }
                .onChange(of: model.network.isOnline) { _, online in
                    guard online else { return }
                    model.recipes.fillMissing(in: context)
                    Task { await model.resumePending() }
                }
        }
    }

    private var tabs: some View {
        @Bindable var model = model
        return TabView(selection: $model.selectedTab) {
            Tab("Semaine", systemImage: "calendar", value: AppModel.Tab.week) {
                WeekView()
            }
            Tab("Journal", systemImage: "checklist", value: AppModel.Tab.journal) {
                JournalView()
            }
            Tab("Courses", systemImage: "cart", value: AppModel.Tab.shopping) {
                ShoppingListView()
            }
            Tab("Recettes", systemImage: "bookmark", value: AppModel.Tab.recipes) {
                RecipesView()
            }
            Tab("Profil", systemImage: "person.crop.circle", value: AppModel.Tab.targets) {
                TargetsView()
            }
        }
        .overlay {
            if let message = model.busyMessage {
                BusyOverlay(message: message, liveMeals: model.liveMeals)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !model.network.isOnline {
                Label("Hors ligne : planning, journal et courses restent disponibles", systemImage: "wifi.slash")
                    .font(Theme.text(.caption, .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Theme.wheat)
                    .accessibilityIdentifier("offlineBanner")
            }
        }
        .sheet(isPresented: $model.needsAIConsent) { AIConsentView() }
        .sheet(isPresented: $model.needsPaywall) { PaywallView() }
        .alert(
            String(localized: "Génération impossible"),
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
    /// Plats déjà reçus (génération de la semaine en flux).
    var liveMeals: [String] = []

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(Theme.display(20, .bold, relativeTo: .headline))
                    .multilineTextAlignment(.center)
                if liveMeals.isEmpty {
                    Text("Ça peut prendre jusqu'à une minute.")
                        .font(Theme.text(.footnote))
                        .foregroundStyle(Theme.muted)
                } else {
                    Text(liveMeals.count > 1 ? "\(liveMeals.count) plats au menu" : "\(liveMeals.count) plat au menu")
                        .font(Theme.text(.subheadline, .semibold))
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(liveMeals.suffix(5).enumerated()), id: \.element) { _, name in
                            Label(name, systemImage: "checkmark.circle.fill")
                                .font(Theme.text(.footnote))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.snappy, value: liveMeals)
                }
            }
            .padding(24)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding(32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("busy")
    }
}
