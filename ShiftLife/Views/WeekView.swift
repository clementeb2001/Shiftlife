import SwiftUI

/// Multi-track week overview: one row per person, columns are the 7 days.
/// Each cell shows the shift (colour + abbreviation) and event dots, so four to
/// five people stay comparable at a glance. Colour is paired with the abbreviation
/// label, never the sole signal.
struct WeekView: View {
    @EnvironmentObject var store: AppStore
    @State private var weekOffset = 0
    @State private var selectedCell: (member: HouseholdMember, day: Date)?

    private let cal = Calendar.current

    private var weekStart: Date {
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) // 1=Sun
        // Make Monday the first day.
        let daysFromMonday = (weekday + 5) % 7
        let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: today)!
        return cal.date(byAdding: .day, value: weekOffset * 7, to: monday)!
    }

    private var days: [Date] {
        (0..<7).map { cal.date(byAdding: .day, value: $0, to: weekStart)! }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekHeader
                ScrollView {
                    VStack(spacing: Theme.Space.m) {
                        dayHeaderRow
                        ForEach(store.data.members) { member in
                            memberRow(member)
                        }
                        legend
                    }
                    .padding(Theme.Space.l)
                    .padding(.bottom, 80)
                }
            }
            .background(Theme.groupedBackground.ignoresSafeArea())
            .navigationTitle("Woche")
            .sheet(item: Binding(
                get: { selectedCell.map { CellSelection(member: $0.member, day: $0.day) } },
                set: { if $0 == nil { selectedCell = nil } }
            )) { sel in
                EditShiftSheet(member: sel.member, day: sel.day)
            }
        }
    }

    private var weekHeader: some View {
        HStack {
            Button { withAnimation { weekOffset -= 1 } } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            VStack {
                Text(rangeLabel).font(.headline)
                if weekOffset == 0 { Text("Diese Woche").font(.caption).foregroundStyle(Theme.subtleText) }
            }
            Spacer()
            Button { withAnimation { weekOffset += 1 } } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
    }

    private var rangeLabel: String {
        "\(Format.dayMonth(days.first!)) – \(Format.dayMonth(days.last!))"
    }

    private var dayHeaderRow: some View {
        HStack(spacing: 4) {
            Text("").frame(width: 64)
            ForEach(days, id: \.self) { day in
                VStack(spacing: 2) {
                    Text(Format.weekdayShort(day)).font(.caption2)
                    Text("\(cal.component(.day, from: day))")
                        .font(.caption.bold())
                        .foregroundStyle(cal.isDateInToday(day) ? .white : .primary)
                        .frame(width: 24, height: 24)
                        .background(cal.isDateInToday(day) ? Theme.brand : .clear, in: Circle())
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func memberRow(_ member: HouseholdMember) -> some View {
        HStack(spacing: 4) {
            VStack(spacing: 2) {
                MemberAvatar(member: member, size: 30)
                Text(member.name.split(separator: " ").first.map(String.init) ?? member.name)
                    .font(.caption2).lineLimit(1)
            }
            .frame(width: 64)

            ForEach(days, id: \.self) { day in
                cell(member: member, day: day)
                    .frame(maxWidth: .infinity)
                    .onTapGesture { selectedCell = (member, day) }
            }
        }
    }

    private func cell(member: HouseholdMember, day: Date) -> some View {
        let inst = store.shiftInstance(for: member.id, on: day)
        let type = inst.flatMap { store.shiftType($0.shiftTypeID) }
        let dayEvents = store.data.events.filter {
            $0.memberIDs.contains(member.id) && cal.isDate($0.start, inSameDayAs: day)
        }
        return VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(type?.color.color ?? Theme.card)
                .overlay(
                    Text(type?.abbreviation ?? "–")
                        .font(.caption2.bold())
                        .foregroundStyle(type == nil ? Theme.subtleText : .white)
                )
                .frame(height: 34)
            HStack(spacing: 2) {
                ForEach(dayEvents.prefix(3)) { ev in
                    Circle().fill(Theme.brand).frame(width: 5, height: 5)
                        .accessibilityLabel(ev.title)
                }
            }
            .frame(height: 6)
        }
    }

    private var legend: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader(title: "Legende", systemImage: "info.circle")
                FlowLayoutSimple(items: store.data.shiftTypes) { t in
                    Chip(text: "\(t.abbreviation) · \(t.name)", color: t.color.color)
                }
                HStack(spacing: 6) {
                    Circle().fill(Theme.brand).frame(width: 6, height: 6)
                    Text("= Termin").font(.caption).foregroundStyle(Theme.subtleText)
                }
                Text("Tippe auf eine Zelle, um den Dienst zu ändern.")
                    .font(.caption).foregroundStyle(Theme.subtleText)
            }
        }
    }
}

private struct CellSelection: Identifiable {
    let member: HouseholdMember
    let day: Date
    var id: String { "\(member.id)-\(day.timeIntervalSince1970)" }
}

/// Very small wrapping layout for chips (avoids importing a full flow-layout dep).
struct FlowLayoutSimple<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        // Simple 2-column grid keeps it predictable across sizes.
        let columns = [GridItem(.adaptive(minimum: 130), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(items) { content($0) }
        }
    }
}
