import SwiftUI

struct CommonTimeView: View {
    @EnvironmentObject var store: AppStore

    @State private var selectedMemberIDs: Set<UUID> = []
    @State private var minDuration: Int = 120
    @State private var timeOfDay: TimeOfDayFilter = .any
    @State private var horizonDays: Int = 14

    enum TimeOfDayFilter: String, CaseIterable, Identifiable {
        case any, morning, afternoon, evening
        var id: String { rawValue }
        var label: String {
            switch self {
            case .any: return "Ganztägig"
            case .morning: return "Vormittag"
            case .afternoon: return "Nachmittag"
            case .evening: return "Abend"
            }
        }
        var range: (Int, Int) {
            switch self {
            case .any: return (0, 24 * 60)
            case .morning: return (6 * 60, 12 * 60)
            case .afternoon: return (12 * 60, 17 * 60)
            case .evening: return (17 * 60, 23 * 60)
            }
        }
    }

    private var partners: [HouseholdMember] { store.data.members.filter { $0.role != .child } }

    private var activeMemberIDs: [UUID] {
        selectedMemberIDs.isEmpty ? partners.map { $0.id } : Array(selectedMemberIDs)
    }

    private var windows: [AvailabilityWindow] {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: horizonDays, to: now)!
        let (lo, hi) = timeOfDay.range
        let q = FreeTimeQuery(memberIDs: activeMemberIDs, rangeStart: now, rangeEnd: end,
                              minimumDurationMinutes: minDuration,
                              earliestMinute: lo, latestMinute: hi)
        return CommonFreeTimeEngine.freeWindows(store: store, query: q)
    }

    private var nextEvening: AvailabilityWindow? {
        CommonFreeTimeEngine.nextEvening(store: store, memberIDs: activeMemberIDs)
    }

    private var freeDaysThisMonth: [Date] {
        CommonFreeTimeEngine.freeDaysInMonth(store: store, memberIDs: activeMemberIDs, monthAnchor: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    highlightCards
                    filterCard
                    resultsCard
                }
                .padding(Theme.Space.l)
                .padding(.bottom, 80)
            }
            .background(Theme.groupedBackground.ignoresSafeArea())
            .navigationTitle("Gemeinsame Zeit")
        }
    }

    private var highlightCards: some View {
        VStack(spacing: Theme.Space.m) {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Nächster gemeinsamer Abend", systemImage: "moon.stars.fill")
                    if let e = nextEvening {
                        Text(Format.windowLabel(e)).font(.title3.bold())
                        Text(Format.duration(minutes: e.durationMinutes) + " Zeit füreinander")
                            .foregroundStyle(Theme.subtleText)
                    } else {
                        Text("Kein freier Abend in Sicht – Filter anpassen oder Urlaub prüfen.")
                            .foregroundStyle(Theme.subtleText)
                    }
                }
            }
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Freie Tage diesen Monat").font(.subheadline).foregroundStyle(Theme.subtleText)
                        Text("\(freeDaysThisMonth.count)").font(.system(size: 40, weight: .bold))
                        Text("Tage ganz ohne Dienst für alle Ausgewählten").font(.caption).foregroundStyle(Theme.subtleText)
                    }
                    Spacer()
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 40)).foregroundStyle(Theme.success)
                }
            }
        }
    }

    private var filterCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Suche gemeinsame Zeit", systemImage: "slider.horizontal.3")

                Text("Personen").font(.subheadline).foregroundStyle(Theme.subtleText)
                FlowLayoutSimple(items: partners) { m in
                    let isOn = activeMemberIDs.contains(m.id)
                    Button {
                        toggle(m.id)
                    } label: {
                        Chip(text: m.name.split(separator: " ").first.map(String.init) ?? m.name,
                             systemImage: isOn ? "checkmark" : "person",
                             color: m.color.color, filled: isOn)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                HStack {
                    Text("Mindestdauer").font(.subheadline)
                    Spacer()
                    Text(Format.duration(minutes: minDuration)).foregroundStyle(Theme.brand).fontWeight(.semibold)
                }
                Picker("Mindestdauer", selection: $minDuration) {
                    Text("30 Min").tag(30)
                    Text("1 Std").tag(60)
                    Text("2 Std").tag(120)
                    Text("4 Std").tag(240)
                    Text("Ganzer Tag").tag(600)
                }
                .pickerStyle(.segmented)

                Text("Tageszeit").font(.subheadline)
                Picker("Tageszeit", selection: $timeOfDay) {
                    ForEach(TimeOfDayFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Zeitraum").font(.subheadline)
                    Spacer()
                    Text("\(horizonDays) Tage").foregroundStyle(Theme.brand).fontWeight(.semibold)
                }
                Picker("Zeitraum", selection: $horizonDays) {
                    Text("7").tag(7); Text("14").tag(14); Text("30").tag(30)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var resultsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Gefundene Zeitfenster", systemImage: "sparkles")
                if windows.isEmpty {
                    EmptyStateView(systemImage: "moon.zzz",
                                   title: "Keine passenden Fenster",
                                   message: "Versuche eine kürzere Mindestdauer, eine andere Tageszeit oder einen längeren Zeitraum.")
                } else {
                    ForEach(windows.prefix(20)) { w in
                        HStack(spacing: Theme.Space.m) {
                            VStack {
                                Text(Format.weekdayShort(w.start)).font(.caption)
                                Text("\(Calendar.current.component(.day, from: w.start))").font(.headline)
                            }
                            .frame(width: 40)
                            .padding(.vertical, 4)
                            .background(Theme.brand.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Format.time(w.start))–\(Format.time(w.end))").fontWeight(.semibold)
                                Text(Format.duration(minutes: w.durationMinutes) + " · " + reason(for: w))
                                    .font(.caption).foregroundStyle(Theme.subtleText)
                            }
                            Spacer()
                            NavigationLink {
                                AddEventView(prefill: w)
                            } label: {
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.brand)
                            }
                        }
                    }
                }
            }
        }
    }

    private func reason(for w: AvailabilityWindow) -> String {
        let names = w.memberIDs.compactMap { store.member($0)?.name.split(separator: " ").first.map(String.init) }
        return "alle frei: " + names.joined(separator: ", ")
    }

    private func toggle(_ id: UUID) {
        if selectedMemberIDs.isEmpty {
            // First tap: start from "all", then remove the un-tapped ones implicitly.
            selectedMemberIDs = Set(partners.map { $0.id })
        }
        if selectedMemberIDs.contains(id) { selectedMemberIDs.remove(id) }
        else { selectedMemberIDs.insert(id) }
        if selectedMemberIDs.isEmpty { /* keep empty -> defaults back to all */ }
    }
}
