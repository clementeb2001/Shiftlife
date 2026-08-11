import SwiftUI

struct ConflictsView: View {
    @EnvironmentObject var store: AppStore
    @State private var editingEvent: CalendarEvent?
    @State private var assigningConflict: Conflict?
    @State private var altEvent: CalendarEvent?
    @State private var reschedTask: TaskItem?

    private var conflicts: [Conflict] { ConflictEngine.detect(store: store) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.m) {
                    if conflicts.isEmpty {
                        Card {
                            EmptyStateView(systemImage: "checkmark.seal.fill",
                                           title: "Keine Konflikte",
                                           message: "Aktuell passen Dienste, Termine und Aufgaben zusammen. Wir melden uns, wenn sich etwas überschneidet.")
                        }
                    } else {
                        ForEach(conflicts) { conflict in
                            conflictCard(conflict)
                        }
                    }
                }
                .padding(Theme.Space.l)
                .padding(.bottom, 80)
            }
            .background(Theme.groupedBackground.ignoresSafeArea())
            .navigationTitle("Konflikte")
            .sheet(item: $editingEvent) { ev in
                AddEventView(existing: ev)
            }
            .sheet(item: $assigningConflict) { c in
                AssignResponsibleSheet(conflict: c)
            }
            .sheet(item: $altEvent) { ev in AlternativeWindowSheet(event: ev) }
            .sheet(item: $reschedTask) { t in RescheduleTaskSheet(task: t) }
        }
    }

    /// One tappable resolution for a conflict.
    struct Resolution: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let action: () -> Void
    }

    /// Builds the concrete resolution options for a conflict (#5 resolver).
    private func resolutions(for conflict: Conflict) -> [Resolution] {
        var out: [Resolution] = []
        if let evID = conflict.eventID, let ev = store.data.events.first(where: { $0.id == evID }) {
            out.append(Resolution(title: "Termin verschieben", icon: "calendar.badge.clock") { editingEvent = ev })
            if conflict.kind == .eventDuringShift || conflict.kind == .eventAfterNightShift {
                out.append(Resolution(title: "Alternativfenster", icon: "arrow.triangle.swap") { altEvent = ev })
            }
        }
        if conflict.kind == .childcareUncovered || conflict.kind == .bothParentsWorking {
            out.append(Resolution(title: "Person zuweisen", icon: "person.badge.plus") { assigningConflict = conflict })
        }
        if let taskID = conflict.taskID, let task = store.data.tasks.first(where: { $0.id == taskID }) {
            out.append(Resolution(title: "Neu terminieren", icon: "calendar") { reschedTask = task })
            out.append(Resolution(title: "Als erledigt", icon: "checkmark.circle") { store.toggleTask(task) })
        }
        return out
    }

    private func conflictCard(_ conflict: Conflict) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(conflict.severity.color.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conflict.title).font(.headline)
                        Text(conflict.detail).font(.subheadline).foregroundStyle(Theme.subtleText)
                    }
                    Spacer()
                }
                Chip(text: "Priorität: \(conflict.severity.label)",
                     systemImage: "flag.fill", color: conflict.severity.color.color)

                Divider()

                // Actionable resolutions – each conflict needs a concrete action.
                FlowChips(items: resolutions(for: conflict)) { r in
                    Button { r.action() } label: { actionLabel(r.title, r.icon) }
                        .buttonStyle(.plain)
                }
                Button {
                    // "Konflikt ignorieren" – MVP: resolve by nudging the event notes.
                    ignore(conflict)
                } label: {
                    Text("Ignorieren").font(.caption).foregroundStyle(Theme.subtleText)
                }
            }
        }
    }

    private func actionLabel(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text).font(.caption).fontWeight(.medium)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.brand.opacity(0.12))
        .foregroundStyle(Theme.brand)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func ignore(_ conflict: Conflict) {
        // Mark event as acknowledged so it drops out of detection for childcare.
        if let evID = conflict.eventID,
           let idx = store.data.events.firstIndex(where: { $0.id == evID }) {
            if conflict.kind == .childcareUncovered || conflict.kind == .bothParentsWorking {
                // Assign current user as responsible to clear the childcare gap.
                store.data.events[idx].responsibleMemberID = store.currentUser.id
            } else {
                store.data.events[idx].notes += "\n[ignoriert]"
            }
        }
    }
}

/// Assign a responsible adult to a childcare conflict's event.
struct AssignResponsibleSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let conflict: Conflict

    private var adults: [HouseholdMember] { store.data.members.filter { $0.role != .child } }

    var body: some View {
        NavigationStack {
            List {
                Section("Wer übernimmt?") {
                    ForEach(adults) { m in
                        Button {
                            assign(m)
                        } label: {
                            HStack {
                                MemberAvatar(member: m, size: 30)
                                Text(m.name)
                                Spacer()
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Person zuweisen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func assign(_ m: HouseholdMember) {
        if let evID = conflict.eventID,
           let idx = store.data.events.firstIndex(where: { $0.id == evID }) {
            store.data.events[idx].responsibleMemberID = m.id
        }
        dismiss()
    }
}

/// Offers to move a clashing event into the next fitting common free window (#5).
struct AlternativeWindowSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let event: CalendarEvent

    private var members: [UUID] {
        event.memberIDs.isEmpty ? [store.currentUser.id] : event.memberIDs
    }
    private var durationMinutes: Int {
        max(30, Int(event.end.timeIntervalSince(event.start) / 60))
    }
    private var window: AvailabilityWindow? {
        CommonFreeTimeEngine.nextWindow(store: store, memberIDs: members, minimumDurationMinutes: durationMinutes)
    }

    var body: some View {
        NavigationStack {
            List {
                if let w = window {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(event.title) · \(Format.duration(minutes: durationMinutes)) – passt hier, alle sind frei:")
                                .font(.subheadline)
                            Text(Format.windowLabel(w)).font(.headline)
                        }
                    }
                    Section {
                        Button {
                            move(to: w.start)
                        } label: { Label("Termin dorthin verschieben", systemImage: "arrow.triangle.swap") }
                    }
                } else {
                    Section {
                        Label("Kein passendes Alternativfenster in den nächsten 3 Wochen.",
                              systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                    }
                }
            }
            .navigationTitle("Alternativfenster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }

    private func move(to start: Date) {
        var e = event
        e.start = start
        e.end = start.addingTimeInterval(Double(durationMinutes) * 60)
        store.upsertEvent(e)
        dismiss()
    }
}

/// Reschedules a task to a day with free time (#5).
struct RescheduleTaskSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    @State private var date = Date()

    private var suggestion: AvailabilityWindow? {
        store.freeWindows(for: store.currentUser.id, days: 21, minMinutes: 60).first
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Neues Datum", selection: $date, displayedComponents: .date)
                if let w = suggestion {
                    Text("Vorschlag: \(Format.relativeDay(w.start)) – da hast du \(Format.duration(minutes: w.durationMinutes)) frei.")
                        .font(.caption).foregroundStyle(Theme.subtleText)
                }
            }
            .navigationTitle("Aufgabe neu terminieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        var t = task; t.dueDate = date; store.upsertTask(t); dismiss()
                    }
                }
            }
            .onAppear { if let w = suggestion { date = w.start } else if let d = task.dueDate { date = d } }
        }
    }
}

#if DEBUG
#Preview("Konflikte") {
    ConflictsView().environmentObject(AppStore.preview)
}
#endif
