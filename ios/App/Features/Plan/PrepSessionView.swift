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
    @Query(sort: \WeeklyPlan.createdAt, order: .reverse) var plans: [WeeklyPlan]

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
            }
        }
        .overlay {
            if plans.isEmpty {
                ContentUnavailableView("Aucun planning", systemImage: "clock")
            }
        }
        .navigationTitle("Historique")
    }
}
