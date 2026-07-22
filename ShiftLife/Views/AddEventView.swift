import SwiftUI

struct AddEventView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var category: EventCategory
    @State private var visibility: Visibility
    @State private var memberIDs: Set<UUID>
    @State private var responsibleID: UUID?
    @State private var notes: String
    @State private var colorOverride: AppColor?
    private let existingID: UUID?

    /// New event.
    init() {
        let now = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
        _title = State(initialValue: "")
        _start = State(initialValue: now)
        _end = State(initialValue: now.addingTimeInterval(3600))
        _category = State(initialValue: .shared)
        _visibility = State(initialValue: .household)
        _memberIDs = State(initialValue: [])
        _responsibleID = State(initialValue: nil)
        _notes = State(initialValue: "")
        _colorOverride = State(initialValue: nil)
        existingID = nil
    }

    /// Prefill from a found free-time window.
    init(prefill window: AvailabilityWindow) {
        _title = State(initialValue: "")
        _start = State(initialValue: window.start)
        _end = State(initialValue: window.end)
        _category = State(initialValue: .shared)
        _visibility = State(initialValue: .household)
        _memberIDs = State(initialValue: Set(window.memberIDs))
        _responsibleID = State(initialValue: nil)
        _notes = State(initialValue: "")
        _colorOverride = State(initialValue: nil)
        existingID = nil
    }

    /// Edit existing.
    init(existing: CalendarEvent) {
        _title = State(initialValue: existing.title)
        _start = State(initialValue: existing.start)
        _end = State(initialValue: existing.end)
        _category = State(initialValue: existing.category)
        _visibility = State(initialValue: existing.visibility)
        _memberIDs = State(initialValue: Set(existing.memberIDs))
        _responsibleID = State(initialValue: existing.responsibleMemberID)
        _notes = State(initialValue: existing.notes)
        _colorOverride = State(initialValue: existing.colorOverride)
        existingID = existing.id
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Termin") {
                    TextField("Titel", text: $title)
                    Picker("Art", selection: $category) {
                        ForEach(EventCategory.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                    }
                }
                Section("Zeit") {
                    DatePicker("Beginn", selection: $start)
                    DatePicker("Ende", selection: $end)
                }
                Section("Beteiligte Personen") {
                    ForEach(store.data.members) { m in
                        Button {
                            if memberIDs.contains(m.id) { memberIDs.remove(m.id) } else { memberIDs.insert(m.id) }
                        } label: {
                            HStack {
                                MemberAvatar(member: m, size: 28)
                                Text(m.name)
                                Spacer()
                                if memberIDs.contains(m.id) {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.brand)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                if category == .childcare {
                    Section("Verantwortlich für Betreuung") {
                        Picker("Person", selection: $responsibleID) {
                            Text("Noch offen").tag(UUID?.none)
                            ForEach(store.data.members.filter { $0.role != .child }) { m in
                                Text(m.name).tag(UUID?.some(m.id))
                            }
                        }
                    }
                }
                Section("Farbe des Termins") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        Button { colorOverride = nil } label: {
                            Text("Auto").font(.system(size: 9, weight: .bold)).foregroundStyle(.primary)
                                .frame(width: 34, height: 34)
                                .background(Theme.card, in: Circle())
                                .overlay(Circle().stroke(colorOverride == nil ? Color.primary : .clear, lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        ForEach(AppColor.pickable) { c in
                            Circle().fill(c.color).frame(width: 34, height: 34)
                                .overlay(Circle().stroke(colorOverride == c ? Color.primary : .clear, lineWidth: 3))
                                .onTapGesture { colorOverride = c }
                                .accessibilityLabel(c.label)
                        }
                    }
                    Text("„Auto“ nutzt die Farbe der beteiligten Person (Kind, sonst Partner, sonst du).")
                        .font(.caption).foregroundStyle(Theme.subtleText)
                }
                Section("Sichtbarkeit") {
                    Picker("Freigabe", selection: $visibility) {
                        ForEach(Visibility.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                    }
                }
                Section("Notiz") {
                    TextField("Optional", text: $notes, axis: .vertical)
                }
                if existingID != nil {
                    Section {
                        Button(role: .destructive) {
                            if let id = existingID, let ev = store.data.events.first(where: { $0.id == id }) {
                                store.deleteEvent(ev); dismiss()
                            }
                        } label: { Text("Termin löschen") }
                    }
                }
            }
            .navigationTitle(existingID == nil ? "Neuer Termin" : "Termin bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        if end <= start { end = start.addingTimeInterval(3600) }
        // Start from the existing event (preserving generated/pickup metadata) or a new one.
        var ev = existingID.flatMap { id in store.data.events.first(where: { $0.id == id }) }
            ?? CalendarEvent(title: "", start: start, end: end, category: category,
                             visibility: visibility, memberIDs: [])
        ev.title = title.trimmingCharacters(in: .whitespaces)
        ev.start = start
        ev.end = end
        ev.category = category
        ev.visibility = visibility
        ev.memberIDs = Array(memberIDs)
        ev.responsibleMemberID = responsibleID
        ev.notes = notes
        ev.colorOverride = colorOverride
        store.upsertEvent(ev)
        dismiss()
    }
}
