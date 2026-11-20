import ShreddishCore
import SwiftUI

/// Apple Santé en option (spec 017, FR-1709) : désactivé tant que l'utilisateur ne l'active pas.
struct HealthSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    var body: some View {
        let health = model.health
        List {
            Section {
                Toggle("Synchroniser avec Santé", isOn: Binding(
                    get: { health.isEnabled },
                    set: { on in
                        if on {
                            Task { await health.enable(container: context.container, clock: model.clock) }
                        } else {
                            health.disable()
                        }
                    }
                ))
                .disabled(!health.isAvailable)
                .accessibilityIdentifier("healthToggle")
            } footer: {
                ListFooter {
                    Text(health.isAvailable
                        ? """
                            Importe tes pesées (balance connectée), lit ta dépense active et enregistre les apports du \
                            journal. Rien ne quitte ton iPhone.
                            """
                        : String(localized: "Apple Santé n'est pas disponible sur cet appareil."))
                }
            }
            if health.isEnabled {
                ThemedSection("Activité mesurée") {
                    LabeledContent(
                        String(localized: "Dépense active"),
                        value: health.averageActiveKcal.map { "\(Format.kcal($0)) / jour" } ?? String(localized: "Pas encore de données")
                    )
                }
            }
            if let error = health.lastError {
                Section {
                    Text(error).foregroundStyle(Theme.tomato)
                }
            }
        }
        .themedList()
        .navigationTitle("Apple Santé")
    }
}
