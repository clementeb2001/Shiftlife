import SwiftUI

/// The "Assistent" screen (V2): Ready-Profiles, adaptive routines, recovery-aware
/// windows, activity suggestions and personal insights. Pushed from Today.
struct AssistView: View {
    @EnvironmentObject var store: AppStore
    @State private var editingType: ShiftType?
    @State private var addingRoutine = false

    private var me: UUID { store.currentUser.id }
    private var readyTypes: [ShiftType] {
        store.data.shiftTypes.filter { $0.counterCategory == .onCall || $0.counterCategory == .work }
    }
    private var recoveryWindows: [AvailabilityWindow] {
        Array(store.freeWindows(for: me, days: 7, minMinutes: 90).prefix(5))
    }
    private var nextWindow: AvailabilityWindow? {
        store.freeWindows(for: me, days: 7, minMinutes: 30).first
    }

    var body: some View {
        List {
            Section {
                Text("Diese Version denkt mit: Vorbereitung, Erholung, Vorschläge und Insights rund um deine Dienste.")
                    .font(.footnote).foregroundStyle(Theme.subtleText)
            }

            // #2 Ready profiles
            Section {
                ForEach(readyTypes) { t in
                    Button { editingType = t } label: {
                        HStack {
                            Circle().fill(t.color.color).frame(width: 12, height: 12)
                            Text(t.name).foregroundStyle(.primary)
                            Spacer()
                            Text("\(store.readyTemplate(for: t).count) Punkte")
                                .font(.caption).foregroundStyle(Theme.subtleText)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleText)
                        }
                    }
                }
            } header: { Text("🎒 Ready-Profile · #2") }
            footer: { Text("Checklisten je Schichtart. Der Fortschritt pro Dienst erscheint auf der Heute-Seite.") }

            // #6 Adaptive routines
            Section {
                if store.data.routines.isEmpty {
                    Text("Noch keine Routinen.").foregroundStyle(Theme.subtleText)
                }
                ForEach(store.data.routines) { r in routineRow(r) }
                    .onDelete { idx in store.data.routines.remove(atOffsets: idx) }
                Button { addingRoutine = true } label: {
                    Label("Routine hinzufügen", systemImage: "plus.circle")
                }
            } header: { Text("🔄 Adaptive Routinen · #6") }
            footer: { Text("Abläufe relativ zum Dienst – verschiebt sich der Dienst, verschiebt sich die Routine mit.") }

            // #7 Recovery-aware windows
            Section {
                if recoveryWindows.isEmpty {
                    Text("Keine freien Fenster in 7 Tagen.").foregroundStyle(Theme.subtleText)
                }
                ForEach(recoveryWindows) { w in
                    let lvl = store.recoveryLevel(for: w, memberID: me)
                    HStack {
                        Text(lvl.emoji)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Format.windowLabel(w)).fontWeight(.medium)
                            Text(Format.duration(minutes: w.durationMinutes) + " frei")
                                .font(.caption).foregroundStyle(Theme.subtleText)
                        }
                        Spacer()
                        Chip(text: lvl.label, color: lvl.appColor.color)
                    }
                }
            } header: { Text("🌙 Erholungs-bewusste Planung · #7") }
            footer: { Text("Nach Nachtdiensten werden Fenster als ungünstig markiert.") }

            // #10 Life-window suggestions
            Section {
                if let w = nextWindow {
                    Text("Nächstes Fenster: \(Format.windowLabel(w)) · \(Format.duration(minutes: w.durationMinutes))")
                        .font(.subheadline)
                    let fit = store.data.activityCategories.filter { $0.minMinutes <= w.durationMinutes }
                    if fit.isEmpty {
                        Text("Keine Aktivität passt in dieses Fenster.").font(.caption).foregroundStyle(Theme.subtleText)
                    } else {
                        FlowChips(items: fit) { c in
                            Button {
                                store.addSuggestion(c, in: w)
                            } label: {
                                Text("\(c.emoji) \(c.label)")
                                    .font(.caption).fontWeight(.medium)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(Theme.brand.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Theme.brand)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text("Aktuell kein passendes Fenster.").foregroundStyle(Theme.subtleText)
                }
            } header: { Text("💡 Zeitfenster-Vorschläge · #10") }
            footer: { Text("Aus freier Zeit wird mit einem Tipp ein Termin.") }

            // #11 Insights
            Section {
                ForEach(store.personalInsights(), id: \.self) { s in
                    HStack(alignment: .top, spacing: 8) {
                        Text("💡")
                        Text(s).font(.subheadline)
                    }
                }
            } header: { Text("📈 Persönliche Insights · #11") }
            footer: { Text("Beobachtungen aus deinen Daten – keine Wertung, nur Muster.") }

            // Commute
            Section {
                Stepper("Arbeitsweg: \(store.data.commuteMinutes) Min",
                        value: $store.data.commuteMinutes, in: 0...180, step: 5)
            } header: { Text("🚗 Arbeitsweg") }
            footer: { Text("Fließt in die Abfahrtszeit auf dem Dashboard ein.") }
        }
        .navigationTitle("Assistent")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingType) { t in ReadyProfileEditor(type: t) }
        .sheet(isPresented: $addingRoutine) { RoutineEditor() }
    }

    private func routineRow(_ r: ShiftRoutine) -> some View {
        HStack {
            Text(r.afterShift ? "🔁" : "⏱️")
            VStack(alignment: .leading, spacing: 1) {
                Text(r.label).fontWeight(.medium)
                Text("\(Format.duration(minutes: r.offsetMinutes)) \(r.afterShift ? "nach Dienstende" : "vor Dienstbeginn")")
                    .font(.caption).foregroundStyle(Theme.subtleText)
            }
            Spacer()
        }
    }
}

/// Edit a shift type's Ready checklist.
struct ReadyProfileEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let type: ShiftType
    @State private var items: [String] = []
    @State private var newItem = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items, id: \.self) { Text($0) }
                        .onDelete { items.remove(atOffsets: $0) }
                    HStack {
                        TextField("Neuer Punkt, z. B. Wecker 04:45", text: $newItem)
                        Button {
                            let v = newItem.trimmingCharacters(in: .whitespaces)
                            guard !v.isEmpty else { return }
                            items.append(v); newItem = ""
                        } label: { Image(systemName: "plus.circle.fill") }
                    }
                } header: { Text("Vor \(type.name) erledigen") }
            }
            .navigationTitle("Ready-Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        var t = type; t.readyItems = items; store.upsertShiftType(t); dismiss()
                    }
                }
            }
            .onAppear { items = store.readyTemplate(for: type) }
        }
    }
}

/// Add an adaptive routine.
struct RoutineEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var minutes = 90
    @State private var afterShift = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Beschreibung, z. B. Essen vorbereiten", text: $label)
                Stepper("\(minutes) Minuten", value: $minutes, in: 0...1440, step: 15)
                Picker("Bezug", selection: $afterShift) {
                    Text("vor Dienstbeginn").tag(false)
                    Text("nach Dienstende").tag(true)
                }
            }
            .navigationTitle("Neue Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        let v = label.trimmingCharacters(in: .whitespaces)
                        guard !v.isEmpty else { return }
                        store.data.routines.append(ShiftRoutine(label: v, offsetMinutes: minutes, afterShift: afterShift))
                        dismiss()
                    }
                }
            }
        }
    }
}

/// The interactive Ready checklist for one shift occurrence.
struct ReadyChecklistView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let inst: ShiftInstance

    private var type: ShiftType? { store.shiftType(inst.shiftTypeID) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(type.map(store.readyTemplate(for:)) ?? [], id: \.self) { item in
                        Button { store.toggleReady(inst, item: item) } label: {
                            HStack {
                                Image(systemName: store.readyDone(inst).contains(item) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(store.readyDone(inst).contains(item) ? Theme.success : Theme.subtleText)
                                Text(item).foregroundStyle(.primary)
                            }
                        }
                    }
                } header: {
                    Text("\(type?.name ?? "Dienst") · \(store.effectiveTimeString(inst))")
                } footer: {
                    Text("Punkte bearbeitest du unter Assistent → Ready-Profile.")
                }
            }
            .navigationTitle("Ready")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}

/// Minimal wrapping chip layout.
struct FlowChips<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 110), spacing: 6)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
            ForEach(items) { content($0) }
        }
    }
}

#if DEBUG
#Preview("Assistent") {
    NavigationStack { AssistView() }.environmentObject(AppStore.preview)
}
#endif
