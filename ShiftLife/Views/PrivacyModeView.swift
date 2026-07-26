import SwiftUI

/// Partner Privacy Mode (#8): choose how much the partner sees. Includes a live
/// preview of the partner's view. Full enforcement applies once iCloud family
/// sharing is active (the sync layer can push `store.redactedForSharing()`).
struct PrivacyModeView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            Section {
                Toggle("Termin-Titel für Partner sichtbar", isOn: $store.data.privacyShareTitles)
            } footer: {
                Text("Aus: die Partnerin sieht nur deine Verfügbarkeit (Zeiten), aber keine Titel oder Notizen.")
            }

            Section {
                previewRow("06:00–14:00", store.data.privacyShareTitles ? "Frühdienst" : "💼 Nicht verfügbar")
                previewRow("15:00–16:00", store.data.privacyShareTitles ? "Arzttermin" : "🔒 Privat")
                previewRow("ab 18:00", "✓ Verfügbar", tint: Theme.success)
            } header: {
                Text("Vorschau – so sieht deine Partnerin deinen Donnerstag")
            } footer: {
                Text("Die volle Trennung greift, sobald der iCloud-Familien-Sync aktiv ist (siehe Familien-Sync).")
            }
        }
        .navigationTitle("Partner Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func previewRow(_ time: String, _ label: String, tint: Color = .primary) -> some View {
        HStack {
            Text(time).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.subtleText)
            Spacer()
            Text(label).foregroundStyle(tint)
        }
    }
}
