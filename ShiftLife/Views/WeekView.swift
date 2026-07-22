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

    // MARK: Woche

    @ViewBuilder private var weekView: some View {
        Card {
            VStack(spacing: Theme.Space.s) {
                weekGridHeader
                ForEach(store.data.members) { m in weekGridRow(m) }
                Text("Zelle tippen = Dienst ändern · Datum tippen = Tagesansicht.")
                    .font(.caption2).foregroundStyle(Theme.subtleText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        weekAgenda
        legend
    }

    private var weekGridHeader: some View {
        HStack(spacing: 4) {
            Text("").frame(width: 56)
            ForEach(weekDays, id: \.self) { day in
                Button { anchor = day; mode = .day } label: {
                    VStack(spacing: 2) {
                        Text(Format.weekdayShort(day)).font(.caption2).foregroundStyle(Theme.subtleText)
                        Text("\(cal.component(.day, from: day))").font(.caption.bold())
                            .foregroundStyle(cal.isDateInToday(day) ? .white : .primary)
                            .frame(width: 24, height: 24)
                            .background(cal.isDateInToday(day) ? Theme.brand : .clear, in: Circle())
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func weekGridRow(_ m: HouseholdMember) -> some View {
        HStack(spacing: 4) {
            VStack(spacing: 2) {
                MemberAvatar(member: m, size: 28)
                Text(firstName(m)).font(.caption2).lineLimit(1)
            }
            .frame(width: 56)
            ForEach(weekDays, id: \.self) { day in
                weekCell(m, day)
                    .frame(maxWidth: .infinity)
                    .onTapGesture { selectedCell = CellSelection(member: m, day: day) }
            }
        }
    }

    private func weekCell(_ m: HouseholdMember, _ day: Date) -> some View {
        let type = shiftType(for: m.id, on: day)
        let dayEvents = store.data.events.filter {
            $0.memberIDs.contains(m.id) && cal.isDate($0.start, inSameDayAs: day)
        }
        return VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(type?.color.color ?? Theme.card)
                .overlay(Text(type?.abbreviation ?? "–").font(.caption2.bold())
                    .foregroundStyle(type == nil ? Theme.subtleText : .white))
                .frame(height: 32)
            HStack(spacing: 2) {
                ForEach(dayEvents.prefix(3)) { ev in
                    Circle().fill(ev.category == .childcare ? Theme.warning : Theme.brand)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 6)
        }
    }

    @ViewBuilder private var weekAgenda: some View {
        if weekDays.allSatisfy({ events(on: $0).isEmpty && tasksDue(on: $0).isEmpty }) {
            Card {
                Text("Keine Termine oder Aufgaben diese Woche.")
                    .font(.caption).foregroundStyle(Theme.subtleText)
            }
        } else {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionHeader(title: "Diese Woche eingetragen", systemImage: "list.bullet")
                    ForEach(weekDays.filter { !events(on: $0).isEmpty || !tasksDue(on: $0).isEmpty }, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(Format.weekdayShort(day)) \(cal.component(.day, from: day)).")
                                .font(.caption.bold()).foregroundStyle(Theme.subtleText)
                            ForEach(events(on: day)) { ev in
                                Button { editingEvent = ev } label: {
                                    HStack(spacing: 6) {
                                        Text(Format.time(ev.start)).font(.caption2).monospacedDigit()
                                            .foregroundStyle(Theme.subtleText)
                                        Image(systemName: ev.category.systemImage).font(.caption2).foregroundStyle(Theme.brand)
                                        Text(ev.title).font(.subheadline).foregroundStyle(.primary)
                                        Spacer()
                                        if isCareOpen(ev) { Text("offen").font(.caption2).foregroundStyle(Theme.warning) }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            ForEach(tasksDue(on: day)) { t in
                                HStack(spacing: 6) {
                                    Image(systemName: "checklist").font(.caption2).foregroundStyle(Theme.subtleText)
                                    Text(t.title).font(.subheadline)
                                }
                            }
                        }
                    }
                }
            }
        }
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
        Card {
            VStack(spacing: 6) {
                HStack {
                    ForEach(["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"], id: \.self) {
                        Text($0).font(.caption2).foregroundStyle(Theme.subtleText).frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(monthCells, id: \.self) { day in monthCell(day) }
                }
                HStack(spacing: 12) {
                    Text("\(firstName(store.currentUser)): Dienst")
                    HStack(spacing: 4) { Circle().fill(Theme.brand).frame(width: 6, height: 6); Text("Termin") }
                    HStack(spacing: 4) { Circle().fill(Theme.warning).frame(width: 6, height: 6); Text("Betreuung") }
                }
                .font(.caption2).foregroundStyle(Theme.subtleText)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func monthCell(_ day: Date) -> some View {
        let inMonth = cal.component(.month, from: day) == cal.component(.month, from: anchor)
        let type = shiftType(for: store.currentUser.id, on: day)
        let dayEvents = events(on: day)
        return Button { anchor = day; mode = .day } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(cal.isDateInToday(day) ? Theme.brand : .primary)
                if let type {
                    Text(type.abbreviation).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(type.color.color, in: Capsule())
                } else {
                    Text(" ").font(.system(size: 9))
                }
                HStack(spacing: 2) {
                    ForEach(dayEvents.prefix(4)) { ev in
                        Circle().fill(ev.category == .childcare ? Theme.warning : Theme.brand)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
            .opacity(inMonth ? 1 : 0.38)
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
                FlowLayoutSimple(items: store.data.shiftTypes) { t in
                    Chip(text: "\(t.abbreviation) · \(t.name)", color: t.color.color)
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
