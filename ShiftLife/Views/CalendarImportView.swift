import SwiftUI
import EventKit

/// Lets the user pull existing appointments from the iOS calendar into ShiftLife
/// so they show up in the plan and trigger conflicts with shifts. Read-only.
struct CalendarImportView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var status: EKAuthorizationStatus = CalendarImport.authorizationStatus
    @State private var candidates: [CalendarImport.Candidate] = []
    @State private var selected: Set<String> = []
    @State private var weeks = 4
    @State private var loading = false
    @State private var importedInfo: String?

    var body: some View {
        NavigationStack {
            Group {
                switch status {
                case .fullAccess:
                    content
                case .denied, .restricted:
                    deniedView
                default:
                    permissionPrompt
                }
            }
            .navigationTitle("Kalender importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
                if canImport {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Importieren (\(selected.count))") { performImport() }
                            .disabled(selected.isEmpty)
                    }
                }
            }
        }
    }

    private var canImport: Bool {
        status == .fullAccess
    }

    // MARK: States

    private var permissionPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 44)).foregroundStyle(Theme.brand)
            Text("Termine aus deinem Gerätekalender laden")
                .font(.headline).multilineTextAlignment(.center)
            Text("ShiftLife liest die Termine nur, um Konflikte mit deinen Diensten zu erkennen. Es wird nichts in deinen Kalender geschrieben.")
                .font(.subheadline).foregroundStyle(Theme.subtleText)
                .multilineTextAlignment(.center)
            Button("Kalenderzugriff erlauben") { requestAccess() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var deniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Kein Kalenderzugriff").font(.headline)
            Text("Bitte erlaube den Zugriff in den iOS-Einstellungen unter Datenschutz › Kalender.")
                .font(.subheadline).foregroundStyle(Theme.subtleText)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var content: some View {
        List {
            Section {
                Picker("Zeitraum", selection: $weeks) {
                    Text("2 Wochen").tag(2)
                    Text("4 Wochen").tag(4)
                    Text("8 Wochen").tag(8)
                    Text("12 Wochen").tag(12)
                }
                .onChange(of: weeks) { _, _ in reload() }
            } footer: {
                if let importedInfo { Text(importedInfo).foregroundStyle(Theme.brand) }
            }

            if loading {
                HStack { ProgressView(); Text("Lade Termine …").foregroundStyle(Theme.subtleText) }
            } else if candidates.isEmpty {
                Text("Keine Termine im gewählten Zeitraum gefunden.")
                    .foregroundStyle(Theme.subtleText)
            } else {
                Section {
                    ForEach(candidates) { c in row(c) }
                } header: {
                    Text("\(candidates.count) Termine")
                }
            }
        }
        .onAppear { if candidates.isEmpty { reload() } }
    }

    private func row(_ c: CalendarImport.Candidate) -> some View {
        Button {
            guard !c.alreadyImported else { return }
            if selected.contains(c.id) { selected.remove(c.id) } else { selected.insert(c.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: c.alreadyImported ? "checkmark.circle.fill"
                        : (selected.contains(c.id) ? "checkmark.circle.fill" : "circle"))
                    .foregroundStyle(c.alreadyImported ? Color.secondary
                        : (selected.contains(c.id) ? Theme.brand : Color.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).foregroundStyle(.primary)
                    Text("\(Self.range(c.start, c.end)) · \(c.calendarName)")
                        .font(.caption).foregroundStyle(Theme.subtleText)
                }
                Spacer()
                if c.alreadyImported {
                    Text("importiert").font(.caption2).foregroundStyle(Theme.subtleText)
                }
            }
        }
        .disabled(c.alreadyImported)
    }

    // MARK: Actions

    private func requestAccess() {
        Task {
            _ = await CalendarImport.requestAccess()
            await MainActor.run {
                status = CalendarImport.authorizationStatus
                if canImport { reload() }
            }
        }
    }

    private func reload() {
        guard canImport else { return }
        loading = true
        importedInfo = nil
        // EventKit fetch is synchronous but can touch disk; hop off the main run loop.
        DispatchQueue.global(qos: .userInitiated).async {
            let result = CalendarImport.candidates(weeks: weeks, existing: store.data.events)
            DispatchQueue.main.async {
                candidates = result
                selected.formIntersection(Set(result.map(\.id)))
                loading = false
            }
        }
    }

    private func performImport() {
        let owner = store.currentUser.id
        let chosen = candidates.filter { selected.contains($0.id) }
            .map { CalendarImport.makeEvent(from: $0, ownerID: owner) }
        let added = store.importEvents(chosen)
        selected.removeAll()
        importedInfo = added == 0 ? "Termine aktualisiert." : "\(added) Termin(e) importiert."
        reload()
    }

    private static func range(_ start: Date, _ end: Date) -> String {
        let df = DateFormatter(); df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "E d.M., HH:mm"
        let tf = DateFormatter(); tf.locale = Locale(identifier: "de_DE"); tf.dateFormat = "HH:mm"
        return "\(df.string(from: start))–\(tf.string(from: end))"
    }
}
