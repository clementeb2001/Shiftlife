import SwiftUI

/// Change a single day's shift for a member without touching the base pattern.
/// Variable-time shifts (e.g. fire-brigade on-call) prompt for an individual
/// time span instead of using a fixed template.
struct EditShiftSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let member: HouseholdMember
    let day: Date

    /// The variable-time type awaiting an individual time span.
    @State private var variableType: ShiftType?
    @State private var startTime = Date()
    @State private var endTime = Date()

    var body: some View {
        NavigationStack {
            Group {
                if let vt = variableType {
                    variableTimeForm(vt)
                } else {
                    typeList
                }
            }
            .navigationTitle("\(member.name.split(separator: " ").first.map(String.init) ?? member.name) · \(Format.relativeDay(day))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if variableType != nil {
                        Button("Zurück") { variableType = nil }
                    } else {
                        Button("Fertig") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var typeList: some View {
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
                        if type.hasVariableTime {
                            prepareVariable(type)
                        } else {
                            store.setShift(memberID: member.id, typeID: type.id, on: day)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Circle().fill(type.color.color).frame(width: 14, height: 14)
                            VStack(alignment: .leading) {
                                Text(type.name)
                                Text(type.hasVariableTime ? "individuelle Zeit" : "\(type.startTimeString)–\(type.endTimeString)")
                                    .font(.caption).foregroundStyle(Theme.subtleText)
                            }
                            Spacer()
                            if type.hasVariableTime {
                                Image(systemName: "clock").foregroundStyle(Theme.subtleText)
                            }
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
    }

    private func variableTimeForm(_ type: ShiftType) -> some View {
        Form {
            Section {
                DatePicker("Von", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("Bis", selection: $endTime, displayedComponents: .hourAndMinute)
            } header: {
                Text("\(type.name) – individuelle Zeit")
            } footer: {
                Text("Zeitspanne für genau diesen Tag. Endet der Dienst am nächsten Tag (über Nacht), Bis-Zeit einfach vor der Von-Zeit wählen.")
            }
            Section {
                Button {
                    store.setShift(memberID: member.id, typeID: type.id, on: day,
                                   startMinutes: minutes(startTime), endMinutes: minutes(endTime))
                    dismiss()
                } label: {
                    Text("Eintragen").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func prepareVariable(_ type: ShiftType) {
        // Prefill from any existing instance of this type, else the type default.
        let cal = Calendar.current
        let existing = store.shiftInstance(for: member.id, on: day)
        let startMin = (existing?.shiftTypeID == type.id ? existing?.startMinutesOverride : nil) ?? type.startMinutes
        let endMin = (existing?.shiftTypeID == type.id ? existing?.endMinutesOverride : nil) ?? type.endMinutes
        startTime = cal.date(bySettingHour: startMin / 60, minute: startMin % 60, second: 0, of: Date()) ?? Date()
        endTime = cal.date(bySettingHour: endMin / 60, minute: endMin % 60, second: 0, of: Date()) ?? Date()
        variableType = type
    }

    private func minutes(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
