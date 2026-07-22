import SwiftUI

/// Central quick-add: shift, event, task, vacation or childcare with minimal taps.
struct QuickAddView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Schnell hinzufügen") {
                    NavigationLink { AddShiftQuick() } label: {
                        quickRow("Dienst eintragen", "briefcase.fill", .blue)
                    }
                    NavigationLink { AddEventView() } label: {
                        quickRow("Termin", "calendar", .teal)
                    }
                    NavigationLink { AddTaskView() } label: {
                        quickRow("Aufgabe", "checklist", .green)
                    }
                    NavigationLink { AddVacationQuick() } label: {
                        quickRow("Urlaub / Frei", "sun.max.fill", .orange)
                    }
                }
                Section("Verwalten") {
                    NavigationLink { ShiftTypesView() } label: {
                        quickRow("Schichtarten & Muster", "square.stack.3d.up.fill", .purple)
                    }
                    NavigationLink { HouseholdView() } label: {
                        quickRow("Meine Personen", "person.2.fill", .indigo)
                    }
                }
            }
            .navigationTitle("Neu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }

    private func quickRow(_ title: String, _ icon: String, _ color: AppColor) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(color.color, in: RoundedRectangle(cornerRadius: 8))
            Text(title).fontWeight(.medium)
        }
    }
}

/// Minimal shift entry: pick person, type, date.
struct AddShiftQuick: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var memberID: UUID?
    @State private var typeID: UUID?
    @State private var date = Date()

    var body: some View {
        Form {
            Picker("Person", selection: $memberID) {
                Text("Auswählen").tag(UUID?.none)
                ForEach(store.data.members) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            Picker("Dienst", selection: $typeID) {
                Text("Frei").tag(UUID?.none)
                ForEach(store.data.shiftTypes) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            DatePicker("Tag", selection: $date, displayedComponents: .date)
            Button("Eintragen") {
                let m = memberID ?? store.currentUser.id
                store.setShift(memberID: m, typeID: typeID, on: date)
                dismiss()
            }
            .disabled(memberID == nil && store.data.members.isEmpty)
        }
        .navigationTitle("Dienst eintragen")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if memberID == nil { memberID = store.currentUser.id } }
    }
}

/// Mark a date range as vacation for a member.
struct AddVacationQuick: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var memberID: UUID?
    @State private var start = Date()
    @State private var end = Date()

    private var vacationType: ShiftType? {
        store.data.shiftTypes.first { $0.counterCategory == .vacation }
    }

    var body: some View {
        Form {
            Picker("Person", selection: $memberID) {
                ForEach(store.data.members) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            DatePicker("Von", selection: $start, displayedComponents: .date)
            DatePicker("Bis", selection: $end, displayedComponents: .date)
            Button("Urlaub eintragen") { apply() }
            if vacationType == nil {
                Label("Es wird automatisch eine Urlaubs-Schichtart angelegt.",
                      systemImage: "info.circle").font(.caption).foregroundStyle(Theme.subtleText)
            }
        }
        .navigationTitle("Urlaub / Frei")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if memberID == nil { memberID = store.currentUser.id } }
    }

    private func apply() {
        let m = memberID ?? store.currentUser.id
        var type = vacationType
        if type == nil {
            let newType = ShiftType(name: "Urlaub", abbreviation: "U", color: .green,
                                    startMinutes: 0, endMinutes: 0, restHours: 0,
                                    counterCategory: .vacation)
            store.addShiftType(newType)
            type = newType
        }
        guard let type else { return }
        let cal = Calendar.current
        var day = cal.startOfDay(for: start)
        let last = cal.startOfDay(for: end)
        while day <= last {
            store.setShift(memberID: m, typeID: type.id, on: day)
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        dismiss()
    }
}
