import Foundation

/// Detects conflicts between events/tasks and shifts. Designed to avoid false or
/// duplicate warnings: each (kind, entity, date) produces at most one conflict.
enum ConflictEngine {

    static func detect(store: AppStore, horizonDays: Int = 21) -> [Conflict] {
        let cal = Calendar.current
        let now = Date()
        let horizon = cal.date(byAdding: .day, value: horizonDays, to: now)!
        var conflicts: [Conflict] = []

        let adults = store.data.members.filter { $0.role != .child }

        for ev in store.data.events {
            guard ev.end >= now, ev.start <= horizon else { continue }

            // 1) Event collides with a shift of an involved member.
            for memberID in ev.memberIDs {
                guard let m = store.member(memberID), m.role != .child else { continue }
                if let clash = shiftClash(store: store, memberID: memberID, start: ev.start, end: ev.end) {
                    conflicts.append(Conflict(
                        kind: .eventDuringShift,
                        severity: .high,
                        title: "\(ev.title) kollidiert mit Schicht",
                        detail: "\(m.name) hat während „\(ev.title)“ \(clash) (\(dateLabel(ev.start))).",
                        date: ev.start,
                        eventID: ev.id,
                        memberIDs: [memberID]))
                }
            }

            // 2) Event directly after a night shift (within rest window) for an involved member.
            for memberID in ev.memberIDs {
                guard let m = store.member(memberID), m.role != .child else { continue }
                if afterNightShift(store: store, memberID: memberID, eventStart: ev.start) {
                    conflicts.append(Conflict(
                        kind: .eventAfterNightShift,
                        severity: .medium,
                        title: "\(ev.title) direkt nach Nachtdienst",
                        detail: "\(m.name) hätte kurz vor „\(ev.title)“ Nachtdienst – wenig Erholung (\(dateLabel(ev.start))).",
                        date: ev.start,
                        eventID: ev.id,
                        memberIDs: [memberID]))
                }
            }

            // 3) Childcare event with no available responsible adult.
            let involvesChild = ev.memberIDs.contains { store.member($0)?.role == .child }
            if ev.category == .childcare || involvesChild {
                let hasResponsible: Bool = {
                    if let resp = ev.responsibleMemberID {
                        return !isBusy(store: store, memberID: resp, start: ev.start, end: ev.end)
                    }
                    return false
                }()
                if !hasResponsible {
                    // Are BOTH adults busy at that time? -> stronger "bothParentsWorking".
                    let availableAdults = adults.filter { !isBusy(store: store, memberID: $0.id, start: ev.start, end: ev.end) }
                    if availableAdults.isEmpty && adults.count >= 1 {
                        conflicts.append(Conflict(
                            kind: .bothParentsWorking,
                            severity: .high,
                            title: "Betreuung nicht abgedeckt: \(ev.title)",
                            detail: "Alle Erwachsenen sind während „\(ev.title)“ eingeteilt (\(dateLabel(ev.start))). Bitte Betreuung klären.",
                            date: ev.start,
                            eventID: ev.id,
                            memberIDs: adults.map { $0.id }))
                    } else {
                        conflicts.append(Conflict(
                            kind: .childcareUncovered,
                            severity: .medium,
                            title: "Keine verantwortliche Person: \(ev.title)",
                            detail: "„\(ev.title)“ hat noch keine zuständige Person (\(dateLabel(ev.start))).",
                            date: ev.start,
                            eventID: ev.id,
                            memberIDs: availableAdults.map { $0.id }))
                    }
                }
            }
        }

        // 4) Open task due soon whose assignee is busy the whole due day (or unassigned).
        for task in store.data.tasks where !task.isDone {
            guard let due = task.dueDate, due >= cal.startOfDay(for: now), due <= horizon else { continue }
            let dayStart = cal.startOfDay(for: due)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!

            if let assignee = task.assigneeID {
                guard let m = store.member(assignee) else { continue }
                // Busy the entire working portion of the day?
                let busy = store.busyIntervals(for: assignee, from: dayStart, to: dayEnd)
                let coversDay = busy.contains { $0.start <= cal.date(byAdding: .hour, value: 8, to: dayStart)! &&
                                                $0.end >= cal.date(byAdding: .hour, value: 20, to: dayStart)! }
                if coversDay {
                    conflicts.append(Conflict(
                        kind: .unassignedTask,
                        severity: .low,
                        title: "Aufgabe evtl. nicht schaffbar: \(task.title)",
                        detail: "\(m.name) ist am \(dateLabel(due)) den ganzen Tag eingeteilt.",
                        date: due,
                        taskID: task.id,
                        memberIDs: [assignee]))
                }
            } else {
                // Unassigned & no adult free that day -> flag.
                let anyFree = adults.contains { !isBusy(store: store, memberID: $0.id,
                                                        start: dayStart, end: dayEnd) }
                if !anyFree && !adults.isEmpty {
                    conflicts.append(Conflict(
                        kind: .unassignedTask,
                        severity: .low,
                        title: "Aufgabe ohne freie Person: \(task.title)",
                        detail: "Am \(dateLabel(due)) ist niemand im Haushalt frei für „\(task.title)“.",
                        date: due,
                        taskID: task.id))
                }
            }
        }

        // De-duplicate identical conflicts and sort by severity then date.
        var seen = Set<String>()
        let unique = conflicts.filter { c in
            let key = "\(c.kind)|\(c.eventID?.uuidString ?? "")|\(c.taskID?.uuidString ?? "")|\(Int(c.date.timeIntervalSince1970))"
            return seen.insert(key).inserted
        }
        return unique.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.date < $1.date
        }
    }

    // MARK: - Helpers

    private static func shiftClash(store: AppStore, memberID: UUID, start: Date, end: Date) -> String? {
        let intervals = store.busyIntervals(for: memberID, from: start, to: end)
        for iv in intervals where iv.overlaps(start: start, end: end) {
            // Only shifts (not other events) count as a "shift clash".
            let isShift = store.data.shiftInstances.contains {
                $0.memberID == memberID &&
                store.shiftType($0.shiftTypeID).map { st in st.name == iv.reason } ?? false
            }
            if isShift { return iv.reason }
        }
        return nil
    }

    private static func isBusy(store: AppStore, memberID: UUID, start: Date, end: Date) -> Bool {
        store.busyIntervals(for: memberID, from: start, to: end).contains { $0.overlaps(start: start, end: end) }
    }

    /// True if the member has a night (rest > 0) shift that ends within its rest
    /// window before the event start.
    private static func afterNightShift(store: AppStore, memberID: UUID, eventStart: Date) -> Bool {
        let cal = Calendar.current
        for inst in store.data.shiftInstances where inst.memberID == memberID {
            guard let type = store.shiftType(inst.shiftTypeID), type.restHours > 0 else { continue }
            let day = cal.startOfDay(for: inst.date)
            var end = cal.date(byAdding: .minute, value: type.endMinutes, to: day)!
            if type.crossesMidnight { end = cal.date(byAdding: .day, value: 1, to: end)! }
            let restEnd = cal.date(byAdding: .hour, value: type.restHours, to: end)!
            if eventStart >= end && eventStart < restEnd { return true }
        }
        return false
    }

    private static func dateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EE d. MMM, HH:mm"
        return f.string(from: date)
    }
}
