import SwiftUI

/// Repas tout juste remplacé : remettre l'ancien (recette et statut compris) ou fermer.
struct UndoReplacementCard: View {
    let name: String
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("« \(name) » a été remplacé.")
                    .font(Theme.text(.subheadline, .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Fermer", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Theme.muted)
                    .frame(minWidth: 44, minHeight: 44)
            }
            Button("Remettre l'ancien repas", action: undo)
                .buttonStyle(PillButtonStyle())
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("undoReplacement")
        }
        .card()
    }
}
