import Foundation
import SwiftUI
import Combine

/// The whole app state in one Codable container, persisted locally as JSON.
/// This is a local-first MVP: everything works offline. A real backend
/// (accounts, household sync, push) is a documented later step – the data model
/// here is deliberately shaped so it can be mapped onto server entities 1:1.
struct AppData: Codable {
    var household: Household
    var members: [HouseholdMember]
    var shiftTypes: [ShiftType]
    var patterns: [ShiftPattern]
    var shiftInstances: [ShiftInstance]
    var events: [CalendarEvent]
    var tasks: [TaskItem]
    var hasCompletedOnboarding: Bool = false
    var isPremium: Bool = false            // paywall gate for family features
    var considerRestAfterNight: Bool = true
    var notifications: NotificationPref = NotificationPref()
    /// When the state was last changed locally. Used for last-writer-wins when
    /// merging with an iCloud copy (see CloudSync). Bumped centrally on save.
    var updatedAt: Date = .distantPast
    /// Opt-in flag for the (prepared) iCloud family sync. Off by default so the
    /// app is fully local until the iCloud capability is enabled on a Mac.
    var syncEnabled: Bool = false

    // MARK: Assistent (V2 features)
    /// Ready-Engine checklist state per shift occurrence: "typeID|dayISO" → done items.
    var readyChecks: [String: [String]] = [:]
    /// Adaptive routines anchored relative to a shift.
    var routines: [ShiftRoutine] = []
    /// Activity categories used for Life-Window suggestions.
    var activityCategories: [ActivityCategory] = []
    /// Commute minutes, used to compute the departure time on the dashboard.
    var commuteMinutes: Int = 25
    /// Smart Shift Detection (#3): monitored work locations + auto-detect flag.
    var workplaces: [Workplace] = []
    var autoDetectEnabled: Bool = false
    /// Partner Privacy Mode (#8): whether event titles are shared with the partner.
    var privacyShareTitles: Bool = false
}

/// Local (on-device) reminder preferences. No server/push needed.
struct NotificationPref: Codable, Equatable {
    var enabled: Bool = false
    var shiftReminders: Bool = true
    var shiftLeadMinutes: Int = 60
    var taskReminders: Bool = true
}

final class AppStore: ObservableObject {
    @Published var data: AppData {
        didSet {
            if stamping || inMemory { return }
            stamping = true
            data.updatedAt = Date()          // re-entrant set; guarded by `stamping`
            stamping = false
            persistence.save(data)
            onLocalChange?(data)             // let the sync layer push, if active
        }
    }
    private var stamping = false

    /// Called after a local change is persisted (used by CloudSync to upload).
    var onLocalChange: ((AppData) -> Void)?

    /// Swappable storage backend. Local today; CloudKit-ready later (see CLOUDKIT.md).
    private let persistence: PersistenceProvider
    private let inMemory: Bool

    // MARK: Init / persistence

    init(inMemory: Bool = false, persistence: PersistenceProvider = LocalJSONPersistence()) {
        self.inMemory = inMemory
        self.persistence = persistence
        if !inMemory, let decoded = persistence.load() {
            data = decoded
        } else {
            data = AppStore.makeSampleData()
        }
        if !inMemory { ensureAssistDefaults() }
    }

    /// Read-only store seeded with an existing snapshot – used by the widget
    /// extension, which must never write back. Nothing is persisted.
    init(readOnly snapshot: AppData) {
        self.inMemory = true
        self.persistence = LocalJSONPersistence()
        self.data = snapshot
    }

    /// Writes the current state to disk immediately (bypasses the debounced
    /// save). For extensions / App Intents that mutate and then exit.
    func flush() { persistence.saveNow(data) }

    /// Adopts a snapshot received from iCloud when it is newer than the local
    /// one. Does not re-stamp or push back, so it can't cause a sync loop.
    func applyRemote(_ remote: AppData) {
        guard remote.updatedAt > data.updatedAt else { return }
        stamping = true
        data = remote
        stamping = false
        persistence.saveNow(data)
    }

    /// Wipes local data (GDPR "vollständige Löschung" requirement).
    func deleteAllData() {
        persistence.wipe()
        data = AppStore.makeSampleData()
        data.hasCompletedOnboarding = false
    }

    /// Export as pretty JSON string (Datenexport requirement).
    func exportJSON() -> String {
        let encoder = JSONEncoder.appEncoder
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let raw = try? encoder.encode(data) else { return "{}" }
        return String(data: raw, encoding: .utf8) ?? "{}"
    }

    // MARK: Convenience lookups

    var currentUser: HouseholdMember {
        data.members.first(where: { $0.isCurrentUser }) ?? data.members[0]
    }

    func member(_ id: UUID?) -> HouseholdMember? {
        guard let id else { return nil }
        return data.members.first(where: { $0.id == id })
    }

    func shiftType(_ id: UUID) -> ShiftType? {
        data.shiftTypes.first(where: { $0.id == id })
    }

    func shiftInstances(on day: Date) -> [ShiftInstance] {
        let d = Calendar.current.startOfDay(for: day)
        return data.shiftInstances.filter { Calendar.current.isDate($0.date, inSameDayAs: d) }
    }

    func shiftInstance(for memberID: UUID, on day: Date) -> ShiftInstance? {
        shiftInstances(on: day).first(where: { $0.memberID == memberID })
    }

    // MARK: Mutations

    func addShiftType(_ t: ShiftType) { data.shiftTypes.append(t) }

    func upsertShiftType(_ t: ShiftType) {
        if let i = data.shiftTypes.firstIndex(where: { $0.id == t.id }) {
            data.shiftTypes[i] = t
        } else {
            data.shiftTypes.append(t)
        }
    }

    func deleteShiftType(_ t: ShiftType) {
        data.shiftTypes.removeAll { $0.id == t.id }
        data.shiftInstances.removeAll { $0.shiftTypeID == t.id }
        for i in data.patterns.indices {
            data.patterns[i].sequence = data.patterns[i].sequence.map { $0 == t.id ? nil : $0 }
        }
    }

    func upsertPattern(_ p: ShiftPattern) {
        if let i = data.patterns.firstIndex(where: { $0.id == p.id }) {
            data.patterns[i] = p
        } else {
            data.patterns.append(p)
        }
    }

    func deletePattern(_ p: ShiftPattern) {
        data.patterns.removeAll { $0.id == p.id }
    }

    /// Applies a pattern to a member over a date range. Manual overrides are kept.
    func applyPattern(_ pattern: ShiftPattern, to memberID: UUID, from start: Date, to end: Date, startIndex: Int = 0) {
        let cal = Calendar.current
        var day = cal.startOfDay(for: start)
        let last = cal.startOfDay(for: end)
        var index = startIndex

        while day <= last {
            let keepManual = data.shiftInstances.first {
                $0.memberID == memberID && cal.isDate($0.date, inSameDayAs: day) && $0.isManualOverride
            }
            if keepManual == nil {
                // remove any non-manual instance on this day for the member
                data.shiftInstances.removeAll {
                    $0.memberID == memberID && cal.isDate($0.date, inSameDayAs: day) && !$0.isManualOverride
                }
                let slot = pattern.sequence[index % pattern.sequence.count]
                if let typeID = slot {
                    data.shiftInstances.append(
                        ShiftInstance(memberID: memberID, shiftTypeID: typeID, date: day)
                    )
                }
            }
            index += 1
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
    }

    func setShift(memberID: UUID, typeID: UUID?, on day: Date,
                  startMinutes: Int? = nil, endMinutes: Int? = nil) {
        let cal = Calendar.current
        let d = cal.startOfDay(for: day)
        data.shiftInstances.removeAll { $0.memberID == memberID && cal.isDate($0.date, inSameDayAs: d) }
        if let typeID {
            data.shiftInstances.append(
                ShiftInstance(memberID: memberID, shiftTypeID: typeID, date: d,
                              isManualOverride: true,
                              startMinutesOverride: startMinutes, endMinutesOverride: endMinutes)
            )
        }
    }

    /// The shift type used for on-call / Bereitschaft duties (by category, then
    /// by the variable-time flag). Creates one on first use if none exists.
    func onCallShiftType() -> ShiftType {
        if let t = data.shiftTypes.first(where: { $0.counterCategory == .onCall }) { return t }
        if let t = data.shiftTypes.first(where: { $0.hasVariableTime }) { return t }
        let new = ShiftType(name: "Bereitschaft", abbreviation: "B", color: .red,
                            startMinutes: 0, endMinutes: 0, restHours: 0,
                            hasVariableTime: true, counterCategory: .onCall)
        data.shiftTypes.append(new)
        return new
    }

    /// Enters parsed duty blocks as on-call shifts for a member. Blocks up to 24h
    /// become a single (possibly overnight) instance; longer ones are split per
    /// day. Identical existing instances are skipped, so re-importing the same
    /// mail does not duplicate. Returns the number of instances created.
    @discardableResult
    func importOnCallBlocks(_ blocks: [ShiftMailParser.DutyBlock], for memberID: UUID? = nil) -> Int {
        guard !blocks.isEmpty else { return 0 }
        let member = memberID ?? currentUser.id
        let type = onCallShiftType()
        let cal = Calendar.current
        var created = 0

        func minutes(_ d: Date) -> Int {
            let c = cal.dateComponents([.hour, .minute], from: d)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }

        func addInstance(day: Date, startMin: Int, endMin: Int) {
            let d = cal.startOfDay(for: day)
            let exists = data.shiftInstances.contains {
                $0.memberID == member && $0.shiftTypeID == type.id &&
                cal.isDate($0.date, inSameDayAs: d) &&
                $0.startMinutesOverride == startMin && $0.endMinutesOverride == endMin
            }
            if exists { return }
            data.shiftInstances.append(
                ShiftInstance(memberID: member, shiftTypeID: type.id, date: d,
                              isManualOverride: true,
                              startMinutesOverride: startMin, endMinutesOverride: endMin))
            created += 1
        }

        for b in blocks {
            let duration = b.end.timeIntervalSince(b.start)
            if duration <= 24 * 3600 {
                addInstance(day: b.start, startMin: minutes(b.start), endMin: minutes(b.end))
            } else {
                // Split a multi-day block into one instance per calendar day.
                var dayStart = b.start
                while dayStart < b.end {
                    let nextMidnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: dayStart))!
                    let segEnd = min(nextMidnight, b.end)
                    let endMin = (segEnd == nextMidnight) ? 0 : minutes(segEnd) // 0 → 24:00 == next midnight
                    addInstance(day: dayStart, startMin: minutes(dayStart), endMin: endMin)
                    dayStart = nextMidnight
                }
            }
        }
        return created
    }

    /// The shift to *display* for a member on a given day. Returns either a
    /// shift that starts that day, or the after-midnight tail of an overnight
    /// shift that started the previous day (so a 22:00–05:00 duty shows on both
    /// days). `isContinuation` marks the second-day tail.
    func dayShift(for memberID: UUID, on day: Date) -> (instance: ShiftInstance, isContinuation: Bool)? {
        if let inst = shiftInstance(for: memberID, on: day) {
            return (inst, false)
        }
        let cal = Calendar.current
        let prev = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: day))!
        if let inst = shiftInstance(for: memberID, on: prev) {
            let m = effectiveMinutes(inst)
            if m.end <= m.start { return (inst, true) }   // crosses midnight → tail today
        }
        return nil
    }

    /// Time label for a shift as shown on a specific day. On the continuation
    /// day the tail is clipped to start at 00:00.
    func shiftDayTimeLabel(_ inst: ShiftInstance, isContinuation: Bool) -> String {
        let m = effectiveMinutes(inst)
        if isContinuation { return "00:00–\(ShiftType.timeString(m.end))" }
        return "\(ShiftType.timeString(m.start))–\(ShiftType.timeString(m.end))"
    }

    /// Effective start/end minutes for an instance (individual override for
    /// variable-time shifts, otherwise the shift type's default).
    func effectiveMinutes(_ inst: ShiftInstance) -> (start: Int, end: Int) {
        let t = shiftType(inst.shiftTypeID)
        return (inst.startMinutesOverride ?? t?.startMinutes ?? 0,
                inst.endMinutesOverride ?? t?.endMinutes ?? 0)
    }

    /// "HH:mm–HH:mm" for an instance's effective times.
    func effectiveTimeString(_ inst: ShiftInstance) -> String {
        let m = effectiveMinutes(inst)
        return "\(ShiftType.timeString(m.start))–\(ShiftType.timeString(m.end))"
    }

    func upsertEvent(_ e: CalendarEvent) {
        if let i = data.events.firstIndex(where: { $0.id == e.id }) {
            data.events[i] = e
        } else {
            data.events.append(e)
        }
    }

    func deleteEvent(_ e: CalendarEvent) { data.events.removeAll { $0.id == e.id } }

    /// Imports events from the device calendar. Events already present (matched
    /// by `externalID`) are updated in place, keeping their ShiftLife id and any
    /// local edits to category/colour. Returns how many were newly added.
    @discardableResult
    func importEvents(_ incoming: [CalendarEvent]) -> Int {
        var added = 0
        for ev in incoming {
            guard let ext = ev.externalID else { continue }
            if let i = data.events.firstIndex(where: { $0.externalID == ext }) {
                // Refresh time/title from the source, keep local classification.
                data.events[i].title = ev.title
                data.events[i].start = ev.start
                data.events[i].end = ev.end
            } else {
                data.events.append(ev)
                added += 1
            }
        }
        return added
    }

    func upsertTask(_ t: TaskItem) {
        if let i = data.tasks.firstIndex(where: { $0.id == t.id }) {
            data.tasks[i] = t
        } else {
            data.tasks.append(t)
        }
    }

    func deleteTask(_ t: TaskItem) { data.tasks.removeAll { $0.id == t.id } }

    func toggleTask(_ t: TaskItem) {
        if let i = data.tasks.firstIndex(where: { $0.id == t.id }) {
            data.tasks[i].isDone.toggle()
        }
    }

    func addMember(_ m: HouseholdMember) { data.members.append(m) }

    func upsertMember(_ m: HouseholdMember) {
        if let i = data.members.firstIndex(where: { $0.id == m.id }) {
            data.members[i] = m
        } else {
            data.members.append(m)
        }
    }

    func deleteMember(_ m: HouseholdMember) {
        guard !m.isCurrentUser else { return }
        data.members.removeAll { $0.id == m.id }
        data.shiftInstances.removeAll { $0.memberID == m.id }
        data.events.removeAll { $0.sourceChildID == m.id }
    }

    // MARK: Childcare / pickups (V1.5)

    /// Upcoming childcare events (manual + generated) within `days`.
    func upcomingChildcare(days: Int = 7) -> [CalendarEvent] {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: now)!
        return data.events
            .filter { $0.category == .childcare && $0.end >= now && $0.start <= end }
            .sorted { $0.start < $1.start }
    }

    /// Regenerates childcare events for a child from its recurring pickups over
    /// the next `horizonDays`. Clears previously generated events for that child.
    @discardableResult
    func regeneratePickupEvents(for childID: UUID, horizonDays: Int = 21) -> Int {
        guard let child = member(childID), !child.pickups.isEmpty else {
            data.events.removeAll { $0.sourceChildID == childID }
            return 0
        }
        data.events.removeAll { $0.sourceChildID == childID }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var created = 0
        for offset in 0..<horizonDays {
            let day = cal.date(byAdding: .day, value: offset, to: today)!
            let weekday = cal.component(.weekday, from: day)
            for p in child.pickups where p.weekday == weekday {
                let start = cal.date(byAdding: .minute, value: p.startMinutes, to: day)!
                let end = cal.date(byAdding: .minute, value: 30, to: start)!
                data.events.append(CalendarEvent(
                    title: "\(p.label) – \(child.name.split(separator: " ").first.map(String.init) ?? child.name)",
                    start: start, end: end, category: .childcare, visibility: .household,
                    memberIDs: [childID], responsibleMemberID: p.responsibleID,
                    isGenerated: true, sourceChildID: childID))
                created += 1
            }
        }
        return created
    }
}

// MARK: - Coding helpers

extension JSONEncoder {
    static var appEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var appDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
