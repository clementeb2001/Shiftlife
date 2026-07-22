import SwiftUI

struct ShiftTypesView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: ShiftType?
    @State private var showAddType = false

    var body: some View {
        List {
            Section("Schichtarten") {
                ForEach(store.data.shiftTypes) { t in
                    Button { editing = t } label: {
                        HStack {
                            Circle().fill(t.color.color).frame(width: 16, height: 16)
                            VStack(alignment: .leading) {
                                Text(t.name).foregroundStyle(.primary)
                                Text("\(t.startTimeString)–\(t.endTimeString) · \(t.counterCategory.label)")
                                    .font(.caption).foregroundStyle(Theme.subtleText)
                            }
                            Spacer()
                            Chip(text: t.abbreviation, color: t.color.color, filled: true)
                        }
                    }
                }
                .onDelete { idx in idx.map { store.data.shiftTypes[$0] }.forEach(store.deleteShiftType) }

                Button {
                    showAddType = true
                } label: { Label("Schichtart hinzufügen", systemImage: "plus") }
            }

            Section {
                NavigationLink { ShiftPatternsView() } label: {
                    Label("Schichtmuster verwalten", systemImage: "square.stack.3d.up.fill")
                }
            } footer: {
                Text("Muster wie F-F-S-S-N-N-Frei können auf einen Zeitraum angewendet werden.")
            }
        }
        .navigationTitle("Schichtarten")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { EditShiftTypeSheet(shiftType: $0) }
        .sheet(isPresented: $showAddType) { EditShiftTypeSheet(shiftType: nil) }
    }
}

struct EditShiftTypeSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var abbreviation: String
    @State private var color: AppColor
    @State private var start: Date
    @State private var end: Date
    @State private var restHours: Int
    @State private var category: ShiftCategory
    private let existingID: UUID?

    init(shiftType: ShiftType?) {
        let cal = Calendar.current
        _name = State(initialValue: shiftType?.name ?? "")
        _abbreviation = State(initialValue: shiftType?.abbreviation ?? "")
        _color = State(initialValue: shiftType?.color ?? .blue)
        _start = State(initialValue: cal.date(bySettingHour: (shiftType?.startMinutes ?? 360) / 60,
                                              minute: (shiftType?.startMinutes ?? 360) % 60, second: 0, of: Date())!)
        _end = State(initialValue: cal.date(bySettingHour: (shiftType?.endMinutes ?? 840) / 60,
                                            minute: (shiftType?.endMinutes ?? 840) % 60, second: 0, of: Date())!)
        _restHours = State(initialValue: shiftType?.restHours ?? 0)
        _category = State(initialValue: shiftType?.counterCategory ?? .work)
        existingID = shiftType?.id
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bezeichnung") {
                    TextField("Name (z. B. Frühdienst)", text: $name)
                    TextField("Kürzel (z. B. F)", text: $abbreviation)
                }
                Section("Zeiten") {
                    DatePicker("Beginn", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Ende", selection: $end, displayedComponents: .hourAndMinute)
                    Stepper("Ruhezeit danach: \(restHours) Std", value: $restHours, in: 0...16)
                }
                Section("Kategorie") {
                    Picker("Kategorie", selection: $category) {
                        ForEach(ShiftCategory.allCases) { Text($0.label).tag($0) }
                    }
                    Text(category.blocksTime ? "Blockiert gemeinsame Zeit." : "Zählt als frei für gemeinsame Zeit.")
                        .font(.caption).foregroundStyle(Theme.subtleText)
                }
                Section("Farbe") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(AppColor.pickable) { c in
                            Circle().fill(c.color)
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(.primary, lineWidth: color == c ? 3 : 0))
                                .onTapGesture { color = c }
                                .accessibilityLabel(c.label)
                        }
                    }
                }
            }
            .navigationTitle(existingID == nil ? "Neue Schichtart" : "Schichtart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }.disabled(name.isEmpty || abbreviation.isEmpty)
                }
            }
        }
    }

    private func minutes(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func save() {
        let t = ShiftType(id: existingID ?? UUID(), name: name, abbreviation: abbreviation,
                          color: color, startMinutes: minutes(start), endMinutes: minutes(end),
                          restHours: restHours, counterCategory: category)
        store.upsertShiftType(t)
        dismiss()
    }
}
