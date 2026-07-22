import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var showExport = false
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
                NavigationLink { StatisticsView() } label: { Label("Meine Statistik", systemImage: "chart.bar.fill") }
                NavigationLink { HouseholdView() } label: { Label("Meine Personen", systemImage: "person.2.fill") }
                NavigationLink { ShiftTypesView() } label: { Label("Schichtarten & Muster", systemImage: "square.stack.3d.up.fill") }
            }

            Section {
                ShareLink(item: CalendarExport.writeICSFile(store: store)) {
                    Label("In Kalender exportieren (.ics)", systemImage: "calendar.badge.plus")
                }
            } header: {
                Text("Kalender")
            } footer: {
                Text("Dienste & Termine der nächsten 8 Wochen als .ics – in Apple oder Google Kalender importierbar.")
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
