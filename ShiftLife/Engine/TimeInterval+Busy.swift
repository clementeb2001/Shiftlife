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
    /// Busy time coming only from shifts (+ optional rest after night).
    func shiftBusyIntervals(for memberID: UUID, from rangeStart: Date, to rangeEnd: Date) -> [BusyInterval] {
        let cal = Calendar.current
        var result: [BusyInterval] = []
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
                result.append(BusyInterval(start: start, end: end, memberID: memberID, reason: type.name))
            }
            if data.considerRestAfterNight && type.restHours > 0 {
                let restEnd = cal.date(byAdding: .hour, value: type.restHours, to: end)!
                if end < rangeEnd && rangeStart < restEnd {
                    result.append(BusyInterval(start: end, end: restEnd, memberID: memberID,
                                               reason: "Ruhezeit nach \(type.name)"))
                }
            }
        }
        return result
    }

    /// Busy time coming from events the member is part of, or responsible for.
    func eventBusyIntervals(for memberID: UUID, from rangeStart: Date, to rangeEnd: Date) -> [BusyInterval] {
        var result: [BusyInterval] = []
        for ev in data.events {
            let involves = ev.memberIDs.contains(memberID) || ev.responsibleMemberID == memberID
            if involves && ev.start < rangeEnd && rangeStart < ev.end {
                result.append(BusyInterval(start: ev.start, end: ev.end, memberID: memberID, reason: ev.title))
            }
        }
        return result
    }

    /// Concrete busy time for a member across [rangeStart, rangeEnd), derived from
    /// shift instances (+ optional rest after night) and events involving them.
    func busyIntervals(for memberID: UUID, from rangeStart: Date, to rangeEnd: Date) -> [BusyInterval] {
        (shiftBusyIntervals(for: memberID, from: rangeStart, to: rangeEnd)
         + eventBusyIntervals(for: memberID, from: rangeStart, to: rangeEnd))
            .sorted { $0.start < $1.start }
    }

    /// Colour used for an event in the calendar = the associated person's colour
    /// (child first, then partner, then me), so all activities with a person share
    /// that person's colour.
    func eventColor(_ ev: CalendarEvent) -> AppColor {
        let ms = ev.memberIDs.compactMap { member($0) }
        if let child = ms.first(where: { $0.role == .child }) { return child.color }
        if let other = ms.first(where: { !$0.isCurrentUser }) { return other.color }
        if let me = ms.first(where: { $0.isCurrentUser }) { return me.color }
        return .slate
    }

    /// Is an adult free to take responsibility for a slot? Considers blocking shifts
    /// (+ rest) and *other* events, deliberately excluding one event by id so an
    /// event's own responsible person isn't counted as busy by that same event.
    func isAdultAvailable(_ memberID: UUID, from: Date, to: Date, excluding eventID: UUID? = nil) -> Bool {
        if shiftBusyIntervals(for: memberID, from: from, to: to)
            .contains(where: { $0.start < to && from < $0.end }) { return false }
        for ev in data.events where ev.id != eventID {
            let involves = ev.memberIDs.contains(memberID) || ev.responsibleMemberID == memberID
            if involves && ev.start < to && from < ev.end { return false }
        }
        return true
    }
}
