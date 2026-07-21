import SwiftUI

struct HouseholdView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: HouseholdMember?
    @State private var showAdd = false

    var body: some View {
        List {
            Section("Haushalt") {
                HStack {
                    Image(systemName: "house.fill").foregroundStyle(Theme.brand)
                    Text(store.data.household.name)
                    Spacer()
                }
                HStack {
                    Text("Einladungscode")
                    Spacer()
                    Text(store.data.household.inviteCode)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Theme.brand)
                }
            } footer: {
                Text("Teile den Code, um Partner:in oder Familie zu verbinden. (Lokale Vorschau – echte Synchronisierung ist ein späterer Backend-Schritt.)")
            }

            Section("Personen") {
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
            }
        }
        .navigationTitle("Haushalt")
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
    private let existingID: UUID?
    private let isCurrentUser: Bool

    init(member: HouseholdMember?) {
        _name = State(initialValue: member?.name ?? "")
        _role = State(initialValue: member?.role ?? .partner)
        _color = State(initialValue: member?.color ?? .green)
        existingID = member?.id
        isCurrentUser = member?.isCurrentUser ?? false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Name", text: $name)
                    Picker("Rolle", selection: $role) {
                        ForEach(MemberRole.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                    }
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
                    Button("Sichern") {
                        let m = HouseholdMember(id: existingID ?? UUID(), name: name, role: role,
                                                color: color, isCurrentUser: isCurrentUser)
                        store.upsertMember(m)
                        dismiss()
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}
