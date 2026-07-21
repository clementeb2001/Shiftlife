import SwiftUI

struct ConflictsView: View {
    @EnvironmentObject var store: AppStore
    @State private var editingEvent: CalendarEvent?
    @State private var assigningConflict: Conflict?

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
        }
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
                HStack(spacing: Theme.Space.s) {
                    if let evID = conflict.eventID,
                       let ev = store.data.events.first(where: { $0.id == evID }) {
                        Button {
                            editingEvent = ev
                        } label: {
                            actionLabel("Termin verschieben", "calendar.badge.clock")
                        }
                    }
                    if conflict.kind == .childcareUncovered || conflict.kind == .bothParentsWorking {
                        Button {
                            assigningConflict = conflict
                        } label: {
                            actionLabel("Person zuweisen", "person.badge.plus")
                        }
                    }
                    if let taskID = conflict.taskID,
                       let task = store.data.tasks.first(where: { $0.id == taskID }) {
                        Button {
                            store.toggleTask(task)
                        } label: {
                            actionLabel("Als erledigt", "checkmark.circle")
                        }
                    }
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
