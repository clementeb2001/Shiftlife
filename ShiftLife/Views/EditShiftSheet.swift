import SwiftUI

/// Change a single day's shift for a member without touching the base pattern.
struct EditShiftSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let member: HouseholdMember
    let day: Date

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        store.setShift(memberID: member.id, typeID: nil, on: day)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "sun.max.fill").foregroundStyle(Theme.success)
                            Text("Frei (kein Dienst)")
                            Spacer()
                            if store.shiftInstance(for: member.id, on: day) == nil {
                                Image(systemName: "checkmark").foregroundStyle(Theme.brand)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }

                Section("Dienst auswählen") {
                    ForEach(store.data.shiftTypes) { type in
                        Button {
                            store.setShift(memberID: member.id, typeID: type.id, on: day)
                            dismiss()
                        } label: {
                            HStack {
                                Circle().fill(type.color.color).frame(width: 14, height: 14)
                                VStack(alignment: .leading) {
                                    Text(type.name)
                                    Text("\(type.startTimeString)–\(type.endTimeString)")
                                        .font(.caption).foregroundStyle(Theme.subtleText)
                                }
                                Spacer()
                                if store.shiftInstance(for: member.id, on: day)?.shiftTypeID == type.id {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.brand)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section {
                    Label("Nur dieser Tag wird geändert. Dein Grundmuster bleibt erhalten.",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(Theme.subtleText)
                }
            }
            .navigationTitle("\(member.name.split(separator: " ").first.map(String.init) ?? member.name) · \(Format.relativeDay(day))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
