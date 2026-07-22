import SwiftUI

/// Settings for on-device reminders. Enabling asks iOS for permission; all
/// scheduling happens locally (no account, no server).
struct NotificationsView: View {
    @EnvironmentObject var store: AppStore
    @State private var denied = false

    var body: some View {
        Form {
            Section {
                Toggle("Erinnerungen aktiv", isOn: enabledBinding)
            } footer: {
                if denied {
                    Text("Mitteilungen für ShiftLife sind in den iOS-Einstellungen deaktiviert. Bitte dort erlauben.")
                } else {
                    Text("Lokale Erinnerungen direkt auf diesem Gerät – kein Konto nötig.")
                }
            }

            if store.data.notifications.enabled {
                Section("Dienste") {
                    Toggle("Vor Dienstbeginn erinnern", isOn: $store.data.notifications.shiftReminders)
                    if store.data.notifications.shiftReminders {
                        Picker("Vorlaufzeit", selection: $store.data.notifications.shiftLeadMinutes) {
                            Text("15 Min").tag(15)
                            Text("30 Min").tag(30)
                            Text("1 Std").tag(60)
                            Text("2 Std").tag(120)
                        }
                    }
                }
                Section("Aufgaben") {
                    Toggle("An fällige Aufgaben erinnern (08:00)", isOn: $store.data.notifications.taskReminders)
                }
            }
        }
        .navigationTitle("Erinnerungen")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: store.data.notifications) { _, _ in
            NotificationManager.reschedule(store.data)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.data.notifications.enabled },
            set: { on in
                if on {
                    Task {
                        let granted = await NotificationManager.requestAuthorization()
                        await MainActor.run {
                            store.data.notifications.enabled = granted
                            denied = !granted
                            NotificationManager.reschedule(store.data)
                        }
                    }
                } else {
                    store.data.notifications.enabled = false
                    NotificationManager.reschedule(store.data)
                }
            }
        )
    }
}
