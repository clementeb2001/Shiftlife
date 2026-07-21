import SwiftUI

struct TasksView: View {
    @EnvironmentObject var store: AppStore
    @State private var showAdd = false
    @State private var editing: TaskItem?
    @State private var filter: Filter = .open

    enum Filter: String, CaseIterable, Identifiable {
        case open, mine, done
        var id: String { rawValue }
        var label: String {
            switch self {
            case .open: return "Offen"
            case .mine: return "Meine"
            case .done: return "Erledigt"
            }
        }
    }

    private var filtered: [TaskItem] {
        let user = store.currentUser.id
        return store.data.tasks
            .filter { t in
                switch filter {
                case .open: return !t.isDone
                case .mine: return !t.isDone && t.assigneeID == user
                case .done: return t.isDone
                }
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(Theme.Space.l)

                ScrollView {
                    VStack(spacing: Theme.Space.m) {
                        if filtered.isEmpty {
                            Card {
                                EmptyStateView(systemImage: "checklist",
                                               title: "Keine Aufgaben",
                                               message: "Füge über das Plus eine gemeinsame oder private Aufgabe hinzu.")
                            }
                        } else {
                            ForEach(filtered) { task in
                                taskRow(task)
                                    .onTapGesture { editing = task }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.bottom, 80)
                }
            }
            .background(Theme.groupedBackground.ignoresSafeArea())
            .navigationTitle("Aufgaben")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddTaskView() }
            .sheet(item: $editing) { AddTaskView(existing: $0) }
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        Card(padding: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                Button { store.toggleTask(task) } label: {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.isDone ? Theme.success : Theme.subtleText)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? Theme.subtleText : .primary)
                    HStack(spacing: 6) {
                        if let due = task.dueDate {
                            Chip(text: Format.relativeDay(due), systemImage: "calendar",
                                 color: due < Date() && !task.isDone ? Theme.danger : Theme.brand)
                        }
                        if task.condition != .none {
                            Chip(text: task.condition.label, systemImage: "wand.and.stars", color: Theme.warning)
                        }
                        if task.repeats {
                            Chip(text: "Wiederholt", systemImage: "repeat", color: Theme.brand)
                        }
                    }
                }
                Spacer()
                if let a = store.member(task.assigneeID) {
                    MemberAvatar(member: a, size: 30)
                } else {
                    Chip(text: "Haushalt", systemImage: "house.fill")
                }
            }
        }
    }
}
