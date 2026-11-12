import ShreddishCore
import SwiftData
import SwiftUI

/// Sessions de batch cooking du planning (FR-014).
struct PrepSessionView: View {
    @Environment(AppModel.self) private var model
    let sessions: [PrepSessionDTO]
    let startDay: LocalDay

    var body: some View {
        List {
            ForEach(sessions, id: \.index) { session in
                Section {
                    LabeledContent("Quand", value: Format.day(startDay.adding(days: session.dayOffset), calendar: model.clock.calendar))
                    LabeledContent("Durée", value: "\(session.durationMinutes) min")
                    ForEach(Array(session.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1).").bold().monospacedDigit()
                            Text(step)
                        }
                    }
                } header: {
                    Text(session.title)
                }
            }
        }
        .navigationTitle("Batch cooking")
    }
}

/// Plannings précédents, consultables hors ligne (FR-013).
struct PlanHistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \WeeklyPlan.createdAt, order: .reverse) var plans: [WeeklyPlan]
    @State private var pendingDeletion: WeeklyPlan?

    var body: some View {
        List {
            ForEach(plans) { plan in
                NavigationLink {
                    WeekPlanList(plan: plan)
                        .navigationTitle(plan.isCurrent ? "Semaine en cours" : "Ancienne semaine")
                } label: {
                    VStack(alignment: .leading) {
                        Text(Format.range(plan, calendar: model.clock.calendar))
                        if plan.isCurrent {
                            Text("En cours").font(.caption).foregroundStyle(.tint)
                        }
                    }
                }
                .swipeActions {
                    Button("Supprimer", systemImage: "trash", role: .destructive) { pendingDeletion = plan }
                }
                .contextMenu {
                    Button("Supprimer ce planning", systemImage: "trash", role: .destructive) { pendingDeletion = plan }
                }
            }
        }
        .confirmationDialog(
            "Supprimer ce planning ?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let plan = pendingDeletion { context.delete(plan) }
                try? context.save()
                pendingDeletion = nil
            }
        } message: {
            Text("Repas, journal et liste de courses de cette semaine sont supprimés. Action irréversible.")
        }
        .overlay {
            if plans.isEmpty {
                ContentUnavailableView("Aucun planning", systemImage: "clock")
            }
        }
        .navigationTitle("Historique")
    }
}
