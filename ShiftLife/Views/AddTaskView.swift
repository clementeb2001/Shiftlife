import SwiftUI

struct AddTaskView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var assigneeID: UUID?
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var condition: TaskCondition
    @State private var visibility: Visibility
    @State private var repeats: Bool
    private let existingID: UUID?

    init() {
        _title = State(initialValue: "")
        _assigneeID = State(initialValue: nil)
        _hasDueDate = State(initialValue: false)
        _dueDate = State(initialValue: Date())
        _condition = State(initialValue: .none)
        _visibility = State(initialValue: .household)
        _repeats = State(initialValue: false)
        existingID = nil
    }

    init(existing: TaskItem) {
        _title = State(initialValue: existing.title)
        _assigneeID = State(initialValue: existing.assigneeID)
        _hasDueDate = State(initialValue: existing.dueDate != nil)
        _dueDate = State(initialValue: existing.dueDate ?? Date())
        _condition = State(initialValue: existing.condition)
        _visibility = State(initialValue: existing.visibility)
        _repeats = State(initialValue: existing.repeats)
        existingID = existing.id
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Aufgabe") {
                    TextField("Was ist zu tun?", text: $title)
                }
                Section("Zuständig") {
                    Picker("Person", selection: $assigneeID) {
                        Label("Ganzer Haushalt", systemImage: "house.fill").tag(UUID?.none)
                        ForEach(store.data.members) { m in
                            Text(m.name).tag(UUID?.some(m.id))
                        }
                    }
                    if assigneeID == nil {
                        Label("Vorschlag: Wird der Person mit der meisten freien Zeit angeboten – keine Zwangszuteilung.",
                              systemImage: "lightbulb")
                            .font(.caption).foregroundStyle(Theme.subtleText)
                    }
                }
                Section("Fälligkeit") {
                    Toggle("Fälligkeitsdatum", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Fällig am", selection: $dueDate, displayedComponents: .date)
                    }
                    Picker("Bedingung", selection: $condition) {
                        ForEach(TaskCondition.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Wiederholen", isOn: $repeats)
                }
                Section("Sichtbarkeit") {
                    Picker("Freigabe", selection: $visibility) {
                        ForEach(Visibility.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                    }
                }
                if existingID != nil {
                    Section {
                        Button(role: .destructive) {
                            if let id = existingID, let t = store.data.tasks.first(where: { $0.id == id }) {
                                store.deleteTask(t); dismiss()
                            }
                        } label: { Text("Aufgabe löschen") }
                    }
                }
            }
            .navigationTitle(existingID == nil ? "Neue Aufgabe" : "Aufgabe bearbeiten")
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
        let t = TaskItem(
            id: existingID ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            isDone: store.data.tasks.first(where: { $0.id == existingID })?.isDone ?? false,
            assigneeID: assigneeID,
            dueDate: hasDueDate ? dueDate : nil,
            condition: condition, visibility: visibility, repeats: repeats)
        store.upsertTask(t)
        dismiss()
    }
}
