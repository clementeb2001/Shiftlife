import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var showExport = false
    @State private var showImport = false
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            Section("Profil") {
                HStack {
                    MemberAvatar(member: store.currentUser, size: 40)
                    VStack(alignment: .leading) {
                        Text(store.currentUser.name).fontWeight(.medium)
                        Text(store.currentUser.role.label).font(.caption).foregroundStyle(Theme.subtleText)
                    }
                }
                NavigationLink { NotificationsView() } label: { Label("Erinnerungen", systemImage: "bell.badge.fill") }
                NavigationLink { SyncSettingsView() } label: { Label("Familien-Sync (iCloud)", systemImage: "arrow.triangle.2.circlepath.icloud.fill") }
                NavigationLink { StatisticsView() } label: { Label("Meine Statistik", systemImage: "chart.bar.fill") }
                NavigationLink { HouseholdView() } label: { Label("Meine Personen", systemImage: "person.2.fill") }
                NavigationLink { ShiftTypesView() } label: { Label("Schichtarten & Muster", systemImage: "square.stack.3d.up.fill") }
            }

            Section {
                NavigationLink { WorkplacesView() } label: { Label("Arbeitsorte & Erkennung", systemImage: "location.fill.viewfinder") }
                NavigationLink { PrivacyModeView() } label: { Label("Partner Privacy", systemImage: "eye.slash.fill") }
            } header: {
                Text("Assistent")
            } footer: {
                Text("Smart Shift Detection erkennt späteres Dienstende (Standort, nur am Gerät). Privacy steuert, was der Partner sieht.")
            }

            Section {
                Button { showImport = true } label: {
                    Label("Termine aus Kalender importieren", systemImage: "calendar.badge.plus")
                }
                ShareLink(item: CalendarExport.writeICSFile(store: store)) {
                    Label("In Kalender exportieren (.ics)", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Kalender")
            } footer: {
                Text("Importiere bestehende Termine, damit sie Konflikte mit deinen Diensten auslösen. Export gibt Dienste & Termine der nächsten 8 Wochen als .ics aus.")
            }

            Section("Planung") {
                Toggle(isOn: $store.data.considerRestAfterNight) {
                    Label("Ruhezeit nach Nachtdienst berücksichtigen", systemImage: "moon.zzz.fill")
                }
            }

            Section {
                Button { showExport = true } label: { Label("Daten exportieren", systemImage: "square.and.arrow.up") }
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("Alle Daten löschen", systemImage: "trash")
                }
            } header: {
                Text("Datenschutz & Daten")
            } footer: {
                Text("Datensparsamkeit: Es werden nur Planungsdaten gespeichert – keine dienstlichen Inhalte. Alles bleibt lokal auf dem Gerät.")
            }

            Section {
                Text("ShiftLife · persönliche iOS-App · lokal auf diesem Gerät")
                    .font(.caption).foregroundStyle(Theme.subtleText)
            }
        }
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showExport) { ExportView(json: store.exportJSON()) }
        .sheet(isPresented: $showImport) { CalendarImportView() }
        .alert("Alle Daten löschen?", isPresented: $showDeleteConfirm) {
            Button("Löschen", role: .destructive) { store.deleteAllData() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dies entfernt Haushalt, Dienste, Termine und Aufgaben unwiderruflich von diesem Gerät.")
        }
    }
}

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    let json: String
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(json).font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("Datenexport (JSON)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
        }
    }
}

#if DEBUG
#Preview("Einstellungen") {
    NavigationStack { SettingsView() }.environmentObject(AppStore.preview)
}
#endif
