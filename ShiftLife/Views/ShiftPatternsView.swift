import SwiftUI

struct ShiftPatternsView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: ShiftPattern?
    @State private var showAdd = false
    @State private var applying: ShiftPattern?

    var body: some View {
        List {
            ForEach(store.data.patterns) { p in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(p.name).fontWeight(.medium)
                    HStack(spacing: 4) {
                        ForEach(Array(p.sequence.enumerated()), id: \.offset) { _, slot in
                            let type = slot.flatMap { store.shiftType($0) }
                            Text(type?.abbreviation ?? "–")
                                .font(.caption2.bold())
                                .frame(width: 24, height: 24)
                                .background((type?.color.color ?? Theme.subtleText).opacity(0.9))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    HStack {
                        Button("Anwenden") { applying = p }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                        Button("Bearbeiten") { editing = p }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
            .onDelete { idx in idx.map { store.data.patterns[$0] }.forEach(store.deletePattern) }

            Button { showAdd = true } label: { Label("Muster hinzufügen", systemImage: "plus") }
        }
        .navigationTitle("Schichtmuster")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { EditPatternSheet(pattern: $0) }
        .sheet(isPresented: $showAdd) { EditPatternSheet(pattern: nil) }
        .sheet(item: $applying) { ApplyPatternSheet(pattern: $0) }
    }
}

struct EditPatternSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var sequence: [UUID?]
    private let existingID: UUID?

    init(pattern: ShiftPattern?) {
        _name = State(initialValue: pattern?.name ?? "")
        _sequence = State(initialValue: pattern?.sequence ?? [nil])
        existingID = pattern?.id
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("z. B. Wechselschicht", text: $name) }
                Section("Abfolge (\(sequence.count) Tage)") {
                    ForEach(Array(sequence.enumerated()), id: \.offset) { i, _ in
                        Picker("Tag \(i + 1)", selection: Binding(
                            get: { sequence[i] },
                            set: { sequence[i] = $0 }
                        )) {
                            Text("Frei").tag(UUID?.none)
                            ForEach(store.data.shiftTypes) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                    }
                    .onDelete { $0.forEach { sequence.remove(at: $0) } }
                    Button { sequence.append(nil) } label: { Label("Tag hinzufügen", systemImage: "plus") }
                }
            }
            .navigationTitle(existingID == nil ? "Neues Muster" : "Muster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        store.upsertPattern(ShiftPattern(id: existingID ?? UUID(), name: name, sequence: sequence))
                        dismiss()
                    }.disabled(name.isEmpty || sequence.isEmpty)
                }
            }
        }
    }
}

struct ApplyPatternSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let pattern: ShiftPattern
    @State private var memberID: UUID?
    @State private var start = Date()
    @State private var weeks = 4

    var body: some View {
        NavigationStack {
            Form {
                Picker("Person", selection: $memberID) {
                    ForEach(store.data.members) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                DatePicker("Startdatum", selection: $start, displayedComponents: .date)
                Stepper("Zeitraum: \(weeks) Wochen", value: $weeks, in: 1...26)
                Section {
                    Label("Manuell geänderte Einzeltage bleiben erhalten.",
                          systemImage: "hand.raised.fill")
                        .font(.caption).foregroundStyle(Theme.subtleText)
                }
                Button("Muster anwenden") {
                    let m = memberID ?? store.currentUser.id
                    let end = Calendar.current.date(byAdding: .day, value: weeks * 7 - 1, to: start)!
                    store.applyPattern(pattern, to: m, from: start, to: end)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Muster anwenden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .onAppear { if memberID == nil { memberID = store.currentUser.id } }
        }
    }
}
