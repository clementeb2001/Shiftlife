import SwiftUI

/// V1.5 feature: simple, personal work-time statistics and vacation overview
/// for the current user. Purely local, read-only – a calm at-a-glance summary.
struct StatisticsView: View {
    @EnvironmentObject var store: AppStore
    @State private var monthOffset = 0

    private let cal = Calendar.current

    private var user: HouseholdMember { store.currentUser }

    private var monthAnchor: Date {
        cal.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    /// All of the user's shift instances within the anchored month.
    private var monthInstances: [ShiftInstance] {
        data.filter { inst in
            inst.memberID == user.id &&
            cal.isDate(inst.date, equalTo: monthAnchor, toGranularity: .month)
        }
    }
    private var data: [ShiftInstance] { store.data.shiftInstances }

    /// Worked minutes = sum of blocking shift durations (rest not counted).
    private var workedMinutes: Int {
        monthInstances.reduce(0) { sum, inst in
            guard let t = store.shiftType(inst.shiftTypeID), t.counterCategory.blocksTime else { return sum }
            var d = t.endMinutes - t.startMinutes
            if d <= 0 { d += 1440 }
            return sum + d
        }
    }

    /// Count per shift type in the month.
    private var byType: [(type: ShiftType, count: Int)] {
        var counts: [UUID: Int] = [:]
        for inst in monthInstances { counts[inst.shiftTypeID, default: 0] += 1 }
        return counts.compactMap { key, c in
            store.shiftType(key).map { ($0, c) }
        }.sorted { $0.count > $1.count }
    }

    private var nightCount: Int {
        monthInstances.filter { store.shiftType($0.shiftTypeID)?.restHours ?? 0 > 0 }.count
    }

    private var workDays: Int {
        monthInstances.filter { store.shiftType($0.shiftTypeID)?.counterCategory.blocksTime ?? false }.count
    }

    // Vacation overview (whole year, all of the user's instances).
    private var vacationDaysThisYear: Int {
        store.data.shiftInstances.filter {
            $0.memberID == user.id &&
            cal.isDate($0.date, equalTo: Date(), toGranularity: .year) &&
            store.shiftType($0.shiftTypeID)?.counterCategory == .vacation
        }.count
    }

    private var nextVacation: Date? {
        store.data.shiftInstances
            .filter { $0.memberID == user.id && $0.date >= cal.startOfDay(for: Date()) &&
                      store.shiftType($0.shiftTypeID)?.counterCategory == .vacation }
            .map { $0.date }.min()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                monthSwitcher
                summaryCard
                breakdownCard
                vacationCard
            }
            .padding(Theme.Space.l)
        }
        .background(Theme.groupedBackground.ignoresSafeArea())
        .navigationTitle("Meine Statistik")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var monthSwitcher: some View {
        HStack {
            Button { withAnimation { monthOffset -= 1 } } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(monthTitle).font(.headline)
            Spacer()
            Button { withAnimation { monthOffset += 1 } } label: { Image(systemName: "chevron.right") }
        }
    }

    private var monthTitle: String {
        let f = DateFormatter(); f.locale = Format.de; f.dateFormat = "MMMM yyyy"
        return f.string(from: monthAnchor)
    }

    private var summaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Arbeitszeit", systemImage: "clock.fill")
                HStack(spacing: Theme.Space.l) {
                    statBlock(value: hoursString(workedMinutes), label: "Stunden")
                    Divider().frame(height: 40)
                    statBlock(value: "\(workDays)", label: "Arbeitstage")
                    Divider().frame(height: 40)
                    statBlock(value: "\(nightCount)", label: "Nachtdienste")
                }
            }
        }
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 26, weight: .bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.subtleText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var breakdownCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Dienste nach Art", systemImage: "chart.bar.fill")
                if byType.isEmpty {
                    Text("Keine Dienste in diesem Monat.").font(.subheadline).foregroundStyle(Theme.subtleText)
                } else {
                    let maxC = byType.map { $0.count }.max() ?? 1
                    ForEach(byType, id: \.type.id) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Circle().fill(item.type.color.color).frame(width: 10, height: 10)
                                Text(item.type.name).font(.subheadline)
                                Spacer()
                                Text("\(item.count)×").font(.subheadline.weight(.semibold)).monospacedDigit()
                            }
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(item.type.color.color)
                                    .frame(width: geo.size.width * CGFloat(item.count) / CGFloat(maxC), height: 6)
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
        }
    }

    private var vacationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader(title: "Urlaubsübersicht", systemImage: "sun.max.fill")
                HStack {
                    Text("\(vacationDaysThisYear)").font(.system(size: 34, weight: .bold)).monospacedDigit()
                    VStack(alignment: .leading) {
                        Text("Urlaubstage").fontWeight(.medium)
                        Text("in \(cal.component(.year, from: Date()))").font(.caption).foregroundStyle(Theme.subtleText)
                    }
                    Spacer()
                    Image(systemName: "beach.umbrella.fill").font(.title).foregroundStyle(Theme.warning)
                }
                if let nv = nextVacation {
                    Divider()
                    Label("Nächster Urlaub: \(Format.relativeDay(nv))", systemImage: "airplane.departure")
                        .font(.subheadline).foregroundStyle(Theme.brand)
                } else {
                    Divider()
                    Text("Kein Urlaub geplant. Über „+“ → Urlaub / Frei eintragen.")
                        .font(.caption).foregroundStyle(Theme.subtleText)
                }
            }
        }
    }

    private func hoursString(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)" : String(format: "%d,%02d", h, Int(round(Double(m) / 60 * 100)))
    }
}
