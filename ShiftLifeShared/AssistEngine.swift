import Foundation

/// Logic for the V2 "Assistent" features: Ready Engine, impact dashboard,
/// adaptive routines, recovery-aware windows, activity suggestions and insights.
/// Pure, on-device, reuses the existing busy/free engines.
extension AppStore {

    // MARK: Defaults / seeding

    static var defaultRoutines: [ShiftRoutine] {
        [ShiftRoutine(label: "Wäsche für den Dienst prüfen", offsetMinutes: 600, afterShift: false),
         ShiftRoutine(label: "Essen vorbereiten", offsetMinutes: 90, afterShift: false),
         ShiftRoutine(label: "Einkauf erledigen", offsetMinutes: 30, afterShift: true)]
    }

    static var defaultActivities: [ActivityCategory] {
        [ActivityCategory(emoji: "🏃", label: "Sport", minMinutes: 60),
         ActivityCategory(emoji: "🛒", label: "Einkauf", minMinutes: 30),
         ActivityCategory(emoji: "🍽️", label: "Gemeinsam essen", minMinutes: 90),
         ActivityCategory(emoji: "🛋️", label: "Erholung", minMinutes: 120),
         ActivityCategory(emoji: "🏛️", label: "Behördengang", minMinutes: 45)]
    }

    /// Seeds routine/activity defaults on first use (empty arrays only).
    func ensureAssistDefaults() {
        if data.routines.isEmpty { data.routines = AppStore.defaultRoutines }
        if data.activityCategories.isEmpty { data.activityCategories = AppStore.defaultActivities }
    }

    // MARK: Shift timing

    func shiftStartDate(_ inst: ShiftInstance) -> Date {
        let m = effectiveMinutes(inst)
        return Calendar.current.date(byAdding: .minute, value: m.start,
                                     to: Calendar.current.startOfDay(for: inst.date))!
    }

    func shiftEndDate(_ inst: ShiftInstance) -> Date {
        let m = effectiveMinutes(inst)
        let day = Calendar.current.startOfDay(for: inst.date)
        var end = Calendar.current.date(byAdding: .minute, value: m.end, to: day)!
        if m.end <= m.start { end = Calendar.current.date(byAdding: .day, value: 1, to: end)! }
        return end
    }

    /// The next shift for a member whose end is still in the future.
    func nextShift(for memberID: UUID) -> ShiftInstance? {
        let now = Date()
        return data.shiftInstances
            .filter { $0.memberID == memberID && shiftEndDate($0) > now }
            .sorted { shiftStartDate($0) < shiftStartDate($1) }
            .first
    }

    /// Departure time = shift start − commute.
    func departureTime(_ inst: ShiftInstance) -> Date {
        Calendar.current.date(byAdding: .minute, value: -max(0, data.commuteMinutes), to: shiftStartDate(inst))!
    }

    // MARK: Ready Engine

    func readyTemplate(for type: ShiftType) -> [String] {
        if !type.readyItems.isEmpty { return type.readyItems }
        switch type.counterCategory {
        case .onCall: return ["Melder/Handy geladen", "Einsatzkleidung griffbereit", "Fahrzeugschlüssel dabei"]
        case .work, .training, .overtime: return ["Wecker gestellt", "Arbeitskleidung bereitgelegt", "Essen eingepackt", "Ausrüstung geprüft"]
        default: return ["Bereit?"]
        }
    }

    func readyKey(_ inst: ShiftInstance) -> String {
        let day = Int(Calendar.current.startOfDay(for: inst.date).timeIntervalSince1970)
        return "\(inst.shiftTypeID.uuidString)|\(day)"
    }

    func readyDone(_ inst: ShiftInstance) -> [String] { data.readyChecks[readyKey(inst)] ?? [] }

    func toggleReady(_ inst: ShiftInstance, item: String) {
        let key = readyKey(inst)
        var arr = data.readyChecks[key] ?? []
        if let i = arr.firstIndex(of: item) { arr.remove(at: i) } else { arr.append(item) }
        data.readyChecks[key] = arr
    }

    func readyProgress(_ inst: ShiftInstance) -> (done: Int, total: Int) {
        let items = readyTemplate(for: shiftType(inst.shiftTypeID) ?? ShiftType(name: "", abbreviation: "", color: .slate, startMinutes: 0, endMinutes: 0))
        let done = readyDone(inst).filter { items.contains($0) }.count
        return (done, items.count)
    }

    // MARK: Free windows (single member) + recovery

    func freeWindows(for memberID: UUID, days: Int, minMinutes: Int) -> [AvailabilityWindow] {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: now))!
        let q = FreeTimeQuery(memberIDs: [memberID], rangeStart: now, rangeEnd: end, minimumDurationMinutes: minMinutes)
        return CommonFreeTimeEngine.freeWindows(store: self, query: q)
    }

    func recoveryLevel(for window: AvailabilityWindow, memberID: UUID) -> RecoveryLevel {
        for inst in data.shiftInstances where inst.memberID == memberID {
            guard let t = shiftType(inst.shiftTypeID), t.restHours > 0 else { continue }
            let end = shiftEndDate(inst)
            let limit = end.addingTimeInterval(Double(t.restHours + 3) * 3600)
            if window.start >= end && window.start < limit { return .unfavorable }
        }
        let h = Calendar.current.component(.hour, from: window.start)
        return (9...20).contains(h) ? .ideal : .possible
    }

    // MARK: Adaptive routines

    /// Concrete fire times of each routine relative to a shift.
    func routineOccurrences(for inst: ShiftInstance) -> [(routine: ShiftRoutine, date: Date)] {
        data.routines.map { r in
            let anchor = r.afterShift ? shiftEndDate(inst) : shiftStartDate(inst)
            let sign: Double = r.afterShift ? 1 : -1
            return (r, anchor.addingTimeInterval(sign * Double(r.offsetMinutes) * 60))
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: Life-window suggestions

    /// Creates a shared event for a suggested activity within a window.
    @discardableResult
    func addSuggestion(_ cat: ActivityCategory, in window: AvailabilityWindow) -> CalendarEvent {
        let cap = window.start.addingTimeInterval(Double(cat.minMinutes) * 60)
        let end = min(window.end, cap)
        let ev = CalendarEvent(title: "\(cat.emoji) \(cat.label)", start: window.start, end: end,
                               category: .shared, visibility: .household,
                               memberIDs: [currentUser.id], notes: "aus Vorschlag")
        upsertEvent(ev)
        return ev
    }

    // MARK: Smart Shift Detection (#3) + Smart Handover (#9)

    /// Applies a detected/edited later end to a shift, recording the overtime.
    /// `newEndMinutes` is minutes from midnight (may be < start = crosses midnight).
    func applyDetectedEnd(instanceID: UUID, newEndMinutes: Int) {
        guard let i = data.shiftInstances.firstIndex(where: { $0.id == instanceID }) else { return }
        let planned = effectiveMinutes(data.shiftInstances[i]).end
        var over = newEndMinutes - planned
        if over < 0 { over += 24 * 60 }
        data.shiftInstances[i].endMinutesOverride = newEndMinutes
        data.shiftInstances[i].isManualOverride = true
        data.shiftInstances[i].overtimeMinutes = over
    }

    /// Childcare/appointments the shift's member is on the hook for that now
    /// overlap the (possibly extended) shift – candidates for handover.
    func handoverCandidates(for inst: ShiftInstance) -> [CalendarEvent] {
        let me = inst.memberID
        let s = shiftStartDate(inst), e = shiftEndDate(inst)
        return data.events
            .filter { ($0.responsibleMemberID == me || $0.memberIDs.contains(me))
                && $0.category != .shared && $0.start < e && $0.end > s }
            .sorted { $0.start < $1.start }
    }

    func reassignEvent(_ ev: CalendarEvent, to memberID: UUID) {
        guard let i = data.events.firstIndex(where: { $0.id == ev.id }) else { return }
        data.events[i].responsibleMemberID = memberID
        if !data.events[i].memberIDs.contains(memberID) { data.events[i].memberIDs.append(memberID) }
    }

    // MARK: Partner Privacy Mode (#8)

    /// A copy of the state suitable for sharing with a partner: when titles are
    /// not shared, event titles/notes are replaced with neutral availability
    /// labels (times stay, so coordination still works). Used by the privacy
    /// preview today; the sync layer can adopt it once iCloud sharing is active.
    func redactedForSharing() -> AppData {
        guard !data.privacyShareTitles else { return data }
        var d = data
        d.events = d.events.map { ev in
            var e = ev
            e.notes = ""
            e.title = (ev.visibility == .privateOnly) ? "Privat" : "Nicht verfügbar"
            return e
        }
        return d
    }

    // MARK: Personal insights

    func personalInsights() -> [String] {
        var out: [String] = []
        let me = currentUser.id
        let myInst = data.shiftInstances.filter { $0.memberID == me }
        let nights = myInst.filter { (shiftType($0.shiftTypeID)?.restHours ?? 0) > 0 }.count
        out.append("Du hast in den nächsten 4 Wochen \(nights) Nachtdienste geplant.")
        let windows = freeWindows(for: me, days: 14, minMinutes: 120).count
        out.append("In den nächsten 2 Wochen gibt es \(windows) freie Fenster von 2 Std oder mehr.")
        let openTasks = data.tasks.filter { !$0.isDone }.count
        if openTasks > 0 {
            out.append("\(openTasks) offene Aufgaben – die meisten lassen sich in ein freies Fenster legen.")
        }
        if nights >= 3 {
            out.append("Faustregel: In Wochen mit vielen Nachtdiensten bleibt weniger gemeinsame Zeit – plane sie bewusst früher ein.")
        }
        return out
    }
}
