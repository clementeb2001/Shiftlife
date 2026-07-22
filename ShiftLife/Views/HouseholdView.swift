import SwiftUI

struct HouseholdView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: HouseholdMember?
    @State private var showAdd = false

    var body: some View {
        List {
            Section {
                ForEach(store.data.members) { m in
                    Button { editing = m } label: {
                        HStack {
                            MemberAvatar(member: m, size: 34)
                            VStack(alignment: .leading) {
                                Text(m.name).foregroundStyle(.primary)
                                Text(m.role.label).font(.caption).foregroundStyle(Theme.subtleText)
                            }
                            Spacer()
                            if m.isCurrentUser { Chip(text: "Du", color: Theme.brand) }
                        }
                    }
                }
                .onDelete { idx in idx.map { store.data.members[$0] }.forEach(store.deleteMember) }

                Button { showAdd = true } label: { Label("Person hinzufügen", systemImage: "person.badge.plus") }
            } header: {
                Text("Personen")
            } footer: {
                Text("Lege Partner:in, Kinder oder weitere Personen als lokale Profile an. Nur so kann ShiftLife eure gemeinsame freie Zeit und Betreuungslücken erkennen. Alles bleibt lokal auf diesem Gerät.")
            }
        }
        .navigationTitle("Meine Personen")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { EditMemberSheet(member: $0) }
        .sheet(isPresented: $showAdd) { EditMemberSheet(member: nil) }
    }
}

struct EditMemberSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var role: MemberRole
    @State private var color: AppColor
    @State private var careInfo: String
    @State private var pickups: [Pickup]
    private let existingID: UUID?
    private let isCurrentUser: Bool

    /// Monday-first weekday order using Calendar weekday numbers (1=Sun…7=Sat).
    private let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    init(member: HouseholdMember?) {
        _name = State(initialValue: member?.name ?? "")
        _role = State(initialValue: member?.role ?? .partner)
        _color = State(initialValue: member?.color ?? .green)
        _careInfo = State(initialValue: member?.careInfo ?? "")
        _pickups = State(initialValue: member?.pickups ?? [])
        existingID = member?.id
        isCurrentUser = member?.isCurrentUser ?? false
    }

    private var adults: [HouseholdMember] { store.data.members.filter { $0.role != .child } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Name", text: $name)
                    Picker("Rolle", selection: $role) {
                        ForEach(MemberRole.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                    }
                }

                if role == .child {
                    Section("Schule / Betreuung") {
                        TextField("z. B. Grundschule, Kita", text: $careInfo)
                    }
                    pickupSection
                }

                Section("Farbe") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(AppColor.allCases) { c in
                            Circle().fill(c.color).frame(width: 34, height: 34)
                                .overlay(Circle().stroke(.primary, lineWidth: color == c ? 3 : 0))
                                .onTapGesture { color = c }
                                .accessibilityLabel(c.label)
                        }
                    }
                }
            }
            .navigationTitle(existingID == nil ? "Neue Person" : "Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save(regenerate: false) }.disabled(name.isEmpty)
                }
            }
        }
    }

    private var pickupSection: some View {
        Section {
            ForEach($pickups) { $p in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Bezeichnung", text: $p.label)
                        .font(.subheadline.weight(.semibold))
                    Picker("Tag", selection: $p.weekday) {
                        ForEach(weekdayOrder, id: \.self) { Text(weekdayName($0)).tag($0) }
                    }
                    DatePicker("Uhrzeit", selection: timeBinding($p), displayedComponents: .hourAndMinute)
                    Picker("Wer holt ab", selection: $p.responsibleID) {
                        Text("Noch offen").tag(UUID?.none)
                        ForEach(adults) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
                .padding(.vertical, 2)
            }
            .onDelete { pickups.remove(atOffsets: $0) }

            Button {
                pickups.append(Pickup(weekday: 2, startMinutes: 15 * 60 + 30))
            } label: { Label("Abholzeit hinzufügen", systemImage: "plus") }

            if existingID != nil && !pickups.isEmpty {
                Button {
                    save(regenerate: true)
                } label: {
                    Label("Abholtermine für 3 Wochen erstellen", systemImage: "calendar.badge.plus")
                }
            }
        } header: {
            Text("Abholzeiten")
        } footer: {
            Text("Wiederkehrende Abholungen. Offene Abholungen (ohne Person) erscheinen als Konflikt, bis jemand zugewiesen ist.")
        }
    }

    // MARK: Helpers

    private func weekdayName(_ wd: Int) -> String {
        ["", "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"][wd]
    }

    private func timeBinding(_ p: Binding<Pickup>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: p.wrappedValue.startMinutes / 60,
                                      minute: p.wrappedValue.startMinutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                p.wrappedValue.startMinutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    private func save(regenerate: Bool) {
        let id = existingID ?? UUID()
        var m = HouseholdMember(id: id, name: name, role: role, color: color, isCurrentUser: isCurrentUser)
        if role == .child {
            m.careInfo = careInfo
            m.pickups = pickups
        }
        store.upsertMember(m)
        if regenerate {
            store.regeneratePickupEvents(for: id)
        }
        dismiss()
    }
}
