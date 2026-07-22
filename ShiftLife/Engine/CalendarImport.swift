import Foundation
import EventKit

/// Reads events from the device calendar (via EventKit) so existing
/// appointments can trigger conflicts with your shifts. Read-only: ShiftLife
/// never writes to the system calendar here (export stays via .ics).
///
/// No account/server involved – EventKit is fully on-device. Requires the
/// `NSCalendarsFullAccessUsageDescription` Info.plist key (set in the project).
enum CalendarImport {
    private static let store = EKEventStore()

    /// A single importable calendar entry, shown for selection before import.
    struct Candidate: Identifiable, Hashable {
        let id: String          // EKEvent.eventIdentifier
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let calendarName: String
        /// True when this external event is already present in ShiftLife.
        var alreadyImported: Bool
    }

    /// Requests read access to the calendar. iOS 17+ full-access API.
    static func requestAccess() async -> Bool {
        await withCheckedContinuation { cont in
            store.requestFullAccessToEvents { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    static var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// Fetches events from all calendars in the given forward window and marks
    /// which ones are already in ShiftLife.
    static func candidates(weeks: Int, existing: [CalendarEvent]) -> [Candidate] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: weeks * 7, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let known = Set(existing.compactMap { $0.externalID })

        return store.events(matching: predicate)
            .filter { !$0.isAllDay }               // all-day events carry no time window for conflicts
            .sorted { $0.startDate < $1.startDate }
            .map { ek in
                Candidate(
                    id: ek.eventIdentifier,
                    title: ek.title ?? "Termin",
                    start: ek.startDate,
                    end: ek.endDate,
                    isAllDay: ek.isAllDay,
                    calendarName: ek.calendar.title,
                    alreadyImported: known.contains(ek.eventIdentifier))
            }
    }

    /// Converts a candidate into a ShiftLife event owned by `ownerID` (the
    /// current user) so it can collide with that person's shifts.
    static func makeEvent(from c: Candidate, ownerID: UUID) -> CalendarEvent {
        CalendarEvent(
            title: c.title,
            start: c.start,
            end: c.end,
            category: .personal,
            visibility: .privateOnly,
            memberIDs: [ownerID],
            notes: "Importiert aus \(c.calendarName)",
            externalID: c.id)
    }
}
