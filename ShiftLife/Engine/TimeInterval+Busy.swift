import Foundation

/// A half-open time interval [start, end). Used as the currency of both engines.
struct BusyInterval: Hashable {
    var start: Date
    var end: Date
    var memberID: UUID
    var reason: String

    func overlaps(_ other: BusyInterval) -> Bool {
        start < other.end && other.start < end
    }
    func overlaps(start s: Date, end e: Date) -> Bool {
        start < e && s < end
    }
}

extension AppStore {
    /// Concrete busy time for a member across [rangeStart, rangeEnd), derived from
    /// shift instances (+ optional rest after night) and events involving them.
    func busyIntervals(for memberID: UUID, from rangeStart: Date, to rangeEnd: Date) -> [BusyInterval] {
        let cal = Calendar.current
        var result: [BusyInterval] = []

        // --- Shifts ---
        for inst in data.shiftInstances where inst.memberID == memberID {
            guard let type = shiftType(inst.shiftTypeID) else { continue }
            guard type.counterCategory.blocksTime else { continue }

            let day = cal.startOfDay(for: inst.date)
            let start = cal.date(byAdding: .minute, value: type.startMinutes, to: day)!
            var end = cal.date(byAdding: .minute, value: type.endMinutes, to: day)!
            if type.crossesMidnight {
                end = cal.date(byAdding: .day, value: 1, to: end)!
            }
            if start < rangeEnd && rangeStart < end {
                result.append(BusyInterval(start: start, end: end, memberID: memberID,
                                           reason: type.name))
            }

            // Rest period after (typically) a night shift.
            if data.considerRestAfterNight && type.restHours > 0 {
                let restEnd = cal.date(byAdding: .hour, value: type.restHours, to: end)!
                if end < rangeEnd && rangeStart < restEnd {
                    result.append(BusyInterval(start: end, end: restEnd, memberID: memberID,
                                               reason: "Ruhezeit nach \(type.name)"))
                }
            }
        }

        // --- Events that involve the member ---
        for ev in data.events where ev.memberIDs.contains(memberID) {
            // A child's own appointment does not make the child "busy" for adult
            // free-time purposes, but it does block the responsible adult.
            if ev.start < rangeEnd && rangeStart < ev.end {
                result.append(BusyInterval(start: ev.start, end: ev.end, memberID: memberID,
                                           reason: ev.title))
            }
        }
        // Childcare events also block the responsible adult even if not in memberIDs.
        for ev in data.events {
            if let resp = ev.responsibleMemberID, resp == memberID,
               !ev.memberIDs.contains(memberID),
               ev.start < rangeEnd && rangeStart < ev.end {
                result.append(BusyInterval(start: ev.start, end: ev.end, memberID: memberID,
                                           reason: ev.title))
            }
        }

        return result.sorted { $0.start < $1.start }
    }
}
