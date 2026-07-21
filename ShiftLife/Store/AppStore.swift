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
}

final class AppStore: ObservableObject {
    @Published var data: AppData {
        didSet { scheduleSave() }
    }

    private let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?

    // MARK: Init / persistence

    init(inMemory: Bool = false) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("shiftlife_data.json")

        if !inMemory,
           let raw = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.appDecoder.decode(AppData.self, from: raw) {
            data = decoded
        } else {
            data = AppStore.makeSampleData()
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = data
        let url = fileURL
        let work = DispatchWorkItem {
            if let raw = try? JSONEncoder.appEncoder.encode(snapshot) {
                try? raw.write(to: url, options: .atomic)
            }
        }
        saveWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Wipes local data (GDPR "vollständige Löschung" requirement).
    func deleteAllData() {
        try? FileManager.default.removeItem(at: fileURL)
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

    func setShift(memberID: UUID, typeID: UUID?, on day: Date) {
        let cal = Calendar.current
        let d = cal.startOfDay(for: day)
        data.shiftInstances.removeAll { $0.memberID == memberID && cal.isDate($0.date, inSameDayAs: d) }
        if let typeID {
            data.shiftInstances.append(
                ShiftInstance(memberID: memberID, shiftTypeID: typeID, date: d, isManualOverride: true)
            )
        }
    }

    func upsertEvent(_ e: CalendarEvent) {
        if let i = data.events.firstIndex(where: { $0.id == e.id }) {
            data.events[i] = e
        } else {
            data.events.append(e)
        }
    }

    func deleteEvent(_ e: CalendarEvent) { data.events.removeAll { $0.id == e.id } }

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
