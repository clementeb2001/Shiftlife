import SwiftUI

/// Calendar view with three modes – Tag / Woche / Monat. Every entry is visible,
/// not just shifts: shifts, appointments, childcare and due tasks all show up.
struct WeekView: View {
    @EnvironmentObject var store: AppStore
    private let cal = Calendar.current

    enum Mode: String, CaseIterable, Identifiable {
        case day, week, month
        var id: String { rawValue }
        var label: String {
            switch self {
            case .day: return "Tag"
            case .week: return "Woche"
            case .month: return "Monat"
            }
        }
    }

    @State private var mode: Mode = .week
    @State private var anchor: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedCell: CellSelection?
    @State private var editingEvent: CalendarEvent?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Ansicht", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, Theme.Space.s)

                header

                ScrollView {
                    VStack(spacing: Theme.Space.m) {
                        switch mode {
                        case .day: dayView
                        case .week: weekView
                        case .month: monthView
                        }
                    }
                    .padding(Theme.Space.l)
                    .padding(.bottom, 80)
                }
            }
            .background(Theme.groupedBackground.ignoresSafeArea())
            .navigationTitle("Kalender")
            .sheet(item: $selectedCell) { sel in EditShiftSheet(member: sel.member, day: sel.day) }
            .sheet(item: $editingEvent) { ev in AddEventView(existing: ev) }
        }
    }

    // MARK: Header / navigation

    private var header: some View {
        HStack {
            Button { shiftAnchor(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Button { anchor = cal.startOfDay(for: Date()) } label: {
                Text(headerTitle).font(.headline).foregroundStyle(.primary)
            }
            Spacer()
            Button { shiftAnchor(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
    }

    private func shiftAnchor(_ n: Int) {
        switch mode {
        case .day: anchor = cal.date(byAdding: .day, value: n, to: anchor)!
        case .week: anchor = cal.date(byAdding: .day, value: n * 7, to: anchor)!
        case .month: anchor = cal.date(byAdding: .month, value: n, to: anchor)!
        }
    }

    private var headerTitle: String {
        switch mode {
        case .day:
            return "\(Format.relativeDay(anchor)) · \(Format.dayMonth(anchor))"
        case .week:
            let mon = weekStart(anchor)
            return "\(Format.dayMonth(mon)) – \(Format.dayMonth(cal.date(byAdding: .day, value: 6, to: mon)!))"
        case .month:
            let f = DateFormatter(); f.locale = Format.de; f.dateFormat = "MMMM yyyy"
            return f.string(from: anchor)
        }
    }

    // MARK: Shared helpers

    private func weekStart(_ d: Date) -> Date {
        let wd = cal.component(.weekday, from: d)
        let fromMon = (wd + 5) % 7
        return cal.date(byAdding: .day, value: -fromMon, to: cal.startOfDay(for: d))!
    }

    private var weekDays: [Date] {
        let mon = weekStart(anchor)
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: mon)! }
    }

    private func firstName(_ m: HouseholdMember) -> String {
        m.name.split(separator: " ").first.map(String.init) ?? m.name
    }

    private func shiftType(for memberID: UUID, on day: Date) -> ShiftType? {
        store.shiftInstance(for: memberID, on: day).flatMap { store.shiftType($0.shiftTypeID) }
    }

    private func events(on day: Date) -> [CalendarEvent] {
        store.data.events
            .filter { cal.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    private func tasksDue(on day: Date) -> [TaskItem] {
        store.data.tasks.filter { $0.dueDate.map { cal.isDate($0, inSameDayAs: day) } ?? false }
    }

    private func participantNames(_ ev: CalendarEvent) -> String {
        ev.memberIDs.compactMap { store.member($0).map(firstName) }.joined(separator: ", ")
    }

    private func isCareOpen(_ ev: CalendarEvent) -> Bool {
        guard ev.category == .childcare else { return false }
        if let resp = ev.responsibleMemberID {
            return !store.isAdultAvailable(resp, from: ev.start, to: ev.end, excluding: ev.id)
        }
        return true
    }

    // MARK: Tag

    @ViewBuilder private var dayView: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader(title: "Dienste & Verfügbarkeit", systemImage: "person.3.fill")
                ForEach(store.data.members) { m in
                    Button { selectedCell = CellSelection(member: m, day: anchor) } label: {
                        HStack {
                            MemberAvatar(member: m, size: 28)
                            Text(firstName(m)).fontWeight(.medium).foregroundStyle(.primary)
                            Spacer()
                            if let t = shiftType(for: m.id, on: anchor) {
                                Chip(text: "\(t.abbreviation) · \(t.startTimeString)–\(t.endTimeString)",
                                     color: t.color.color, filled: true)
                            } else {
                                Chip(text: "frei", systemImage: "checkmark", color: Theme.success)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Text("Tippe auf eine Person, um den Dienst zu ändern.")
                    .font(.caption).foregroundStyle(Theme.subtleText)
            }
        }
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader(title: "Termine & Betreuung", systemImage: "calendar")
                if events(on: anchor).isEmpty {
                    Text("Keine Termine.").font(.subheadline).foregroundStyle(Theme.subtleText)
                } else {
                    ForEach(events(on: anchor)) { ev in eventRow(ev) }
                }
            }
        }
        if !tasksDue(on: anchor).isEmpty {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionHeader(title: "Aufgaben fällig", systemImage: "checklist")
                    ForEach(tasksDue(on: anchor)) { t in taskRow(t) }
                }
            }
        }
    }

    private func eventRow(_ ev: CalendarEvent) -> some View {
        Button { editingEvent = ev } label: {
            HStack {
                Text(Format.time(ev.start)).font(.caption).monospacedDigit()
                    .foregroundStyle(Theme.subtleText).frame(width: 44, alignment: .leading)
                Image(systemName: ev.category.systemImage).foregroundStyle(Theme.brand)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ev.title).fontWeight(.medium).foregroundStyle(.primary)
                    if !participantNames(ev).isEmpty {
                        Text(participantNames(ev)).font(.caption2).foregroundStyle(Theme.subtleText)
                    }
                }
                Spacer()
                if isCareOpen(ev) { Chip(text: "offen", color: Theme.warning) }
            }
        }
        .buttonStyle(.plain)
    }

    private func taskRow(_ t: TaskItem) -> some View {
        HStack {
            Button { store.toggleTask(t) } label: {
                Image(systemName: t.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(t.isDone ? Theme.success : Theme.subtleText)
            }
            .buttonStyle(.plain)
            Text(t.title).strikethrough(t.isDone)
                .foregroundStyle(t.isDone ? Theme.subtleText : .primary)
            Spacer()
            if let a = store.member(t.assigneeID) { MemberAvatar(member: a, size: 24) }
            else { Chip(text: "Haushalt", systemImage: "house.fill") }
        }
    }

    // MARK: Pills

    private func adultsWithShift(on day: Date) -> [HouseholdMember] {
        store.data.members.filter { $0.role != .child && shiftType(for: $0.id, on: day) != nil }
    }

    private func openTasks(on day: Date) -> [TaskItem] {
        store.data.tasks.filter { !$0.isDone && ($0.dueDate.map { cal.isDate($0, inSameDayAs: day) } ?? false) }
    }

    private func shiftPill(_ m: HouseholdMember, _ t: ShiftType, day: Date, compact: Bool, full: Bool) -> some View {
        Text(compact ? t.abbreviation : t.name)
            .font(.system(size: compact ? 8.5 : 10, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(compact ? 1 : 2)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(minHeight: full ? (compact ? 30 : 52) : 0)
            .padding(.horizontal, 4).padding(.vertical, compact ? 2 : 4)
            .background(t.color.color, in: RoundedRectangle(cornerRadius: compact ? 4 : 6))
            .contentShape(Rectangle())
            .onTapGesture { selectedCell = CellSelection(member: m, day: day) }
    }

    private func eventPill(_ ev: CalendarEvent, compact: Bool) -> some View {
        let c = store.eventColor(ev).color
        return Text(ev.title)
            .font(.system(size: compact ? 8 : 10, weight: .semibold))
            .foregroundStyle(c)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4).padding(.vertical, compact ? 2 : 3)
            .background(c.opacity(0.16), in: RoundedRectangle(cornerRadius: compact ? 4 : 6))
            .overlay(RoundedRectangle(cornerRadius: compact ? 4 : 6)
                .stroke(Theme.warning, lineWidth: isCareOpen(ev) ? 1.5 : 0))
            .contentShape(Rectangle())
            .onTapGesture { editingEvent = ev }
    }

    private func taskPill(_ t: TaskItem, compact: Bool) -> some View {
        Text("✓ \(t.title)")
            .font(.system(size: compact ? 8 : 10, weight: .semibold))
            .foregroundStyle(Theme.subtleText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4).padding(.vertical, compact ? 2 : 3)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: compact ? 4 : 6))
    }

    /// Vertical stack of pills for a day: shifts (solid) fill when nothing else,
    /// then events (person colour) and tasks. `cap` limits events in month cells.
    private func dayPillStack(_ day: Date, compact: Bool, cap: Int? = nil, showTasks: Bool = true) -> some View {
        let shiftMembers = adultsWithShift(on: day)
        let evs = events(on: day)
        let tks = showTasks ? openTasks(on: day) : []
        let full = evs.isEmpty && tks.isEmpty
        let shownEvs = cap.map { Array(evs.prefix($0)) } ?? evs
        let overflow = cap.map { max(0, evs.count - $0) } ?? 0
        return VStack(spacing: compact ? 2 : 4) {
            ForEach(shiftMembers) { m in
                if let t = shiftType(for: m.id, on: day) {
                    shiftPill(m, t, day: day, compact: compact, full: full)
                }
            }
            ForEach(shownEvs) { ev in eventPill(ev, compact: compact) }
            ForEach(tks) { t in taskPill(t, compact: compact) }
            if overflow > 0 {
                Text("+\(overflow)").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.subtleText).frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Woche

    @ViewBuilder private var weekView: some View {
        Card(padding: Theme.Space.m) {
            VStack(spacing: 6) {
                HStack(alignment: .top, spacing: 5) {
                    ForEach(weekDays, id: \.self) { day in
                        VStack(spacing: 5) {
                            Button { anchor = day; mode = .day } label: {
                                VStack(spacing: 1) {
                                    Text(Format.weekdayShort(day)).font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Theme.subtleText)
                                    Text("\(cal.component(.day, from: day))").font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(cal.isDateInToday(day) ? .white : .primary)
                                        .frame(width: 22, height: 22)
                                        .background(cal.isDateInToday(day) ? Theme.brand : .clear, in: Circle())
                                }
                            }
                            .buttonStyle(.plain)
                            dayPillStack(day, compact: false)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                Text("Schicht tippen = ändern · Termin tippen = bearbeiten · Kopf = Tag.")
                    .font(.caption2).foregroundStyle(Theme.subtleText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        legend
    }

    // MARK: Monat

    private var monthCells: [Date] {
        let comps = cal.dateComponents([.year, .month], from: anchor)
        let first = cal.date(from: comps)!
        let wd = cal.component(.weekday, from: first)
        let lead = (wd + 5) % 7
        let start = cal.date(byAdding: .day, value: -lead, to: first)!
        return (0..<42).map { cal.date(byAdding: .day, value: $0, to: start)! }
    }

    @ViewBuilder private var monthView: some View {
        Card(padding: Theme.Space.m) {
            VStack(spacing: 6) {
                HStack {
                    ForEach(["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"], id: \.self) {
                        Text($0).font(.caption2).foregroundStyle(Theme.subtleText).frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), alignment: .center, spacing: 4) {
                    ForEach(monthCells, id: \.self) { day in monthCell(day) }
                }
            }
        }
        legend
    }

    private func monthCell(_ day: Date) -> some View {
        let inMonth = cal.component(.month, from: day) == cal.component(.month, from: anchor)
        return Button { anchor = day; mode = .day } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(cal.isDateInToday(day) ? Theme.brand : .primary)
                    .frame(maxWidth: .infinity)
                dayPillStack(day, compact: true, cap: 3, showTasks: false)
                Spacer(minLength: 0)
            }
            .padding(3)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .top)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
            .opacity(inMonth ? 1 : 0.4)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(cal.isDateInToday(day) ? Theme.brand : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: Legend

    private var legend: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader(title: "Legende", systemImage: "info.circle")
                Text("Schichten (volle Farbe)").font(.caption).foregroundStyle(Theme.subtleText)
                FlowLayoutSimple(items: store.data.shiftTypes) { t in
                    Text(t.name).font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(t.color.color, in: Capsule())
                }
                Text("Personen (Termine in dieser Farbe)").font(.caption).foregroundStyle(Theme.subtleText)
                FlowLayoutSimple(items: store.data.members) { m in
                    Text(firstName(m)).font(.caption2.bold()).foregroundStyle(m.color.color)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(m.color.color.opacity(0.16), in: Capsule())
                }
            }
        }
    }
}

struct CellSelection: Identifiable {
    let member: HouseholdMember
    let day: Date
    var id: String { "\(member.id)-\(day.timeIntervalSince1970)" }
}

/// Very small wrapping layout for chips (avoids importing a full flow-layout dep).
struct FlowLayoutSimple<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 130), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(items) { content($0) }
        }
    }
}
