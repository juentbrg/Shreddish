import ShreddishCore
import SwiftUI
import UIKit

/// Réglages des rappels (spec 016) : chaque rappel activable, avec son heure.
struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var notifications = model.notifications
        List {
            if notifications.authorization == .denied {
                Section {
                    Button("Autoriser dans Réglages iOS") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                } footer: {
                    ListFooter {
                        Text("Notifications refusées pour Shreddish : aucun rappel ne s'affichera.")
                    }
                }
            }
            ThemedSection("Repas") {
                Toggle("Rappel à chaque repas", isOn: $notifications.settings.mealsEnabled)
                    .accessibilityIdentifier("mealReminders")
                if notifications.settings.mealsEnabled {
                    Picker("Moment", selection: $notifications.settings.mealLeadMinutes) {
                        ForEach(NotificationSettings.leadOptions, id: \.self) { minutes in
                            Text(minutes == 0 ? String(localized: "À l'heure") : String(localized: "\(minutes) min avant")).tag(minutes)
                        }
                    }
                }
            }
            reminder(
                "Pesée", toggle: "Rappel de pesée", enabled: $notifications.settings.weighInEnabled,
                minutes: $notifications.settings.weighInMinutes, footer: "Chaque jour, sauf si tu t'es déjà pesé."
            )
            reminder(
                "Suite du planning", toggle: "Planifier la semaine suivante",
                enabled: $notifications.settings.planNextEnabled, minutes: $notifications.settings.planNextMinutes,
                footer: "La veille du dernier jour planifié."
            )
            reminder(
                "Batch cooking", toggle: "Jour de préparation", enabled: $notifications.settings.prepEnabled,
                minutes: $notifications.settings.prepMinutes, footer: "Les jours de session, si le batch cooking est activé."
            )
            reminder(
                "Courses", toggle: "Liste de courses", enabled: $notifications.settings.shoppingEnabled,
                minutes: $notifications.settings.shoppingMinutes,
                footer: "Premier jour du planning, s'il reste des articles à cocher."
            )
        }
        .themedList()
        .navigationTitle("Notifications")
        .task { await model.notifications.requestAuthorizationIfNeeded() }
    }

    private func reminder(
        _ title: String, toggle: String, enabled: Binding<Bool>, minutes: Binding<Int>, footer: String
    ) -> some View {
        Section {
            Toggle(LocalizedStringKey(toggle), isOn: enabled)
            if enabled.wrappedValue {
                DatePicker("Heure", selection: Binding(
                    get: {
                        Calendar.current.date(
                            bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: .now
                        ) ?? .now
                    },
                    set: {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                        minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                    }
                ), displayedComponents: .hourAndMinute)
            }
        } header: {
            ListHeader {
                Text(LocalizedStringKey(title))
            }
        } footer: {
            ListFooter {
                Text(LocalizedStringKey(footer))
            }
        }
    }
}
