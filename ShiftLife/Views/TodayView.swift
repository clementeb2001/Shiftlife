import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: AppStore

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private var conflicts: [Conflict] { ConflictEngine.detect(store: store) }

    private var nextWindow: AvailabilityWindow? {
        let partners = store.data.members.filter { $0.role != .child }.map { $0.id }
        return CommonFreeTimeEngine.nextWindow(store: store, memberIDs: partners, minimumDurationMinutes: 120)
    }

    private var todaysEvents: [CalendarEvent] {
        store.data.events
            .filter { Calendar.current.isDate($0.start, inSameDayAs: Date()) }
            .sorted { $0.start < $1.start }
    }

    private var openTasksToday: [TaskItem] {
        store.data.tasks.filter { !$0.isDone && ($0.dueDate.map { Calendar.current.isDateInToday($0) || $0 < Date() } ?? false) }
    }

    private var upcomingCare: [CalendarEvent] { store.upcomingChildcare(days: 7) }

    @State private var assigningEvent: CalendarEvent?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    myShiftCard
                    availabilityCard
                    if !conflicts.isEmpty { conflictsSummary }
                    nextTogetherCard
                    if !upcomingCare.isEmpty { careCard }
                    if !todaysEvents.isEmpty { eventsCard }
                    if !openTasksToday.isEmpty { tasksCard }
                }
                .padding(Theme.Space.l)
                .padding(.bottom, 80)
            }
            .background(Theme.groupedBackground.ignoresSafeArea())
            .navigationTitle("Heute")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(item: $assigningEvent) { ev in AssignEventSheet(event: ev) }
        }
    }

    // MARK: Betreuung / Abholung

    private func isCovered(_ ev: CalendarEvent) -> Bool {
        guard let resp = ev.responsibleMemberID else { return false }
        return store.isAdultAvailable(resp, from: ev.start, to: ev.end, excluding: ev.id)
    }

    private var careCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Betreuung & Abholung", systemImage: "figure.and.child.holdinghands")
                ForEach(upcomingCare.prefix(5)) { ev in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ev.title).fontWeight(.medium)
                            Text("\(Format.relativeDay(ev.start)) · \(Format.time(ev.start))")
                                .font(.caption).foregroundStyle(Theme.subtleText)
                        }
                        Spacer()
                        if isCovered(ev), let who = store.member(ev.responsibleMemberID) {
                            Chip(text: who.name.split(separator: " ").first.map(String.init) ?? who.name,
                                 systemImage: "checkmark", color: Theme.success)
                        } else {
                            Button { assigningEvent = ev } label: {
                                Chip(text: "Zuweisen", systemImage: "person.badge.plus", color: Theme.warning)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("Abholzeiten pflegst du unter Einstellungen → Meine Personen → Kind.")
                    .font(.caption).foregroundStyle(Theme.subtleText)
            }
        }
    }

    // MARK: Cards

    private var myShiftCard: some View {
        let user = store.currentUser
        let inst = store.shiftInstance(for: user.id, on: today)
        let type = inst.flatMap { store.shiftType($0.shiftTypeID) }
        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    MemberAvatar(member: user, size: 40)
                    VStack(alignment: .leading) {
                        Text(Format.full(today)).font(.caption).foregroundStyle(Theme.subtleText)
                        Text("Dein Dienst heute").font(.headline)
                    }
                    Spacer()
                }
                if let type {
                    HStack(spacing: Theme.Space.m) {
                        RoundedRectangle(cornerRadius: 6).fill(type.color.color).frame(width: 6, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.name).font(.title3.bold())
                            Text("\(type.startTimeString)–\(type.endTimeString)")
                                .foregroundStyle(Theme.subtleText)
                        }
                        Spacer()
                        Chip(text: type.abbreviation, color: type.color.color, filled: true)
                    }
                    if type.restHours > 0 {
                        Label("Ruhezeit: \(type.restHours) Std nach Dienstende",
                              systemImage: "moon.zzz.fill")
                            .font(.caption).foregroundStyle(Theme.subtleText)
                    }
                } else {
                    HStack {
                        Image(systemName: "sun.max.fill").foregroundStyle(Theme.success)
                        Text("Frei – kein Dienst heute").font(.title3.bold())
                    }
                }
            }
        }
    }

    private var availabilityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Wer ist verfügbar?", systemImage: "person.3.fill")
                ForEach(store.data.members) { m in
                    HStack {
                        MemberAvatar(member: m, size: 30)
                        Text(m.name).fontWeight(.medium)
                        Spacer()
                        availabilityBadge(for: m)
                    }
                }
            }
        }
    }

    private func availabilityBadge(for m: HouseholdMember) -> some View {
        let inst = store.shiftInstance(for: m.id, on: today)
        let type = inst.flatMap { store.shiftType($0.shiftTypeID) }
        return Group {
            if let type {
                Chip(text: "\(type.name) · \(type.startTimeString)–\(type.endTimeString)",
                     systemImage: "briefcase.fill", color: type.color.color)
            } else {
                Chip(text: "Frei", systemImage: "checkmark", color: Theme.success)
            }
        }
    }

    private var conflictsSummary: some View {
        NavigationLink {
            ConflictsView()
        } label: {
            Card {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2).foregroundStyle(Theme.danger)
                    VStack(alignment: .leading) {
                        Text("\(conflicts.count) \(conflicts.count == 1 ? "Konflikt" : "Konflikte")")
                            .font(.headline)
                        Text(conflicts.first?.title ?? "")
                            .font(.subheadline).foregroundStyle(Theme.subtleText)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.subtleText)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var nextTogetherCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader(title: "Nächste gemeinsame Zeit", systemImage: "heart.fill")
                if let w = nextWindow {
                    Text(Format.windowLabel(w)).font(.title3.bold())
                    Text(Format.duration(minutes: w.durationMinutes) + " am Stück frei")
                        .foregroundStyle(Theme.subtleText)
                } else {
                    Text("Kein gemeinsames Fenster in den nächsten 3 Wochen gefunden.")
                        .foregroundStyle(Theme.subtleText)
                    Label("Tipp: Urlaub oder Tausch prüfen", systemImage: "lightbulb")
                        .font(.caption).foregroundStyle(Theme.warning)
                }
            }
        }
    }

    private var eventsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Termine heute", systemImage: "calendar")
                ForEach(todaysEvents) { ev in
                    HStack {
                        Image(systemName: ev.category.systemImage).foregroundStyle(Theme.brand)
                        VStack(alignment: .leading) {
                            Text(ev.title).fontWeight(.medium)
                            Text("\(Format.time(ev.start))–\(Format.time(ev.end))")
                                .font(.caption).foregroundStyle(Theme.subtleText)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private var tasksCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Fällige Aufgaben", systemImage: "checklist")
                ForEach(openTasksToday) { t in
                    HStack {
                        Button { store.toggleTask(t) } label: {
                            Image(systemName: t.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(t.isDone ? Theme.success : Theme.subtleText)
                        }
                        Text(t.title)
                        Spacer()
                        if let a = store.member(t.assigneeID) {
                            MemberAvatar(member: a, size: 24)
                        } else {
                            Chip(text: "Haushalt", systemImage: "house.fill", color: Theme.brand)
                        }
                    }
                }
            }
        }
    }
}

/// Assigns a responsible adult to a single childcare event.
struct AssignEventSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let event: CalendarEvent

    private var adults: [HouseholdMember] { store.data.members.filter { $0.role != .child } }

    var body: some View {
        NavigationStack {
            List {
                Section("Wer übernimmt \(event.title)?") {
                    ForEach(adults) { m in
                        Button {
                            var e = event
                            e.responsibleMemberID = m.id
                            store.upsertEvent(e)
                            dismiss()
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
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
