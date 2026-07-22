import Foundation

/// Exports shifts and events to an iCalendar (.ics) file that can be imported
/// into Apple/Google Calendar. No permissions needed – the file is shared via
/// the system share sheet (see SettingsView). A later step can add direct
/// EventKit writing once the app ships.
enum CalendarExport {
    static func icsString(store: AppStore, weeks: Int = 8) -> String {
        let cal = Calendar.current
        let now = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: weeks * 7, to: now)!

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyyMMdd'T'HHmmss'Z'"

        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//ShiftLife//DE", "CALSCALE:GREGORIAN"]

        func appendEvent(uid: String, start: Date, end: Date, summary: String) {
            let clean = summary.replacingOccurrences(of: "\n", with: " ")
            lines += ["BEGIN:VEVENT", "UID:\(uid)@shiftlife",
                      "DTSTART:\(df.string(from: start))", "DTEND:\(df.string(from: end))",
                      "SUMMARY:\(clean)", "END:VEVENT"]
        }

        for inst in store.data.shiftInstances where inst.date >= now && inst.date <= end {
            guard let t = store.shiftType(inst.shiftTypeID) else { continue }
            let day = cal.startOfDay(for: inst.date)
            let m = store.effectiveMinutes(inst)
            let s = cal.date(byAdding: .minute, value: m.start, to: day)!
            var e = cal.date(byAdding: .minute, value: m.end, to: day)!
            if m.end <= m.start { e = cal.date(byAdding: .day, value: 1, to: e)! }
            let who = store.member(inst.memberID).map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name } ?? ""
            appendEvent(uid: inst.id.uuidString, start: s, end: e,
                        summary: (who.isEmpty ? "" : "\(who): ") + t.name)
        }

        for ev in store.data.events where ev.start >= now && ev.start <= end {
            appendEvent(uid: ev.id.uuidString, start: ev.start, end: ev.end, summary: ev.title)
        }

        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n")
    }

    /// Writes the .ics to a temporary file and returns its URL (for ShareLink).
    static func writeICSFile(store: AppStore) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ShiftLife.ics")
        try? icsString(store: store).data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
}
