import Foundation

/// Extracts on-call (Bereitschaft) duty periods from a confirmation e-mail such
/// as the fire-brigade duty roster ("Affectations créées", columns Début/Fin
/// with `TT-MM-JJJJ HH:MM` timestamps). A single duty is usually split into many
/// consecutive one-hour position slots; those are merged back into one block.
///
/// Pure, on-device, no network. Shared by the in-app paste screen, the Share
/// Extension and the App Intent so all three behave identically.
enum ShiftMailParser {

    struct DutyBlock: Equatable, Identifiable {
        var start: Date
        var end: Date
        var id: String { "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)" }
    }

    /// Parse merged duty blocks from raw e-mail text.
    static func parse(_ raw: String, now: Date = Date()) -> [DutyBlock] {
        // Only look at the "created" part: cut the text off at a deletion heading
        // so cancelled/removed shifts are never imported.
        let text = truncatedBeforeDeletions(raw)

        let dates = dateTimes(in: text)
        guard dates.count >= 2 else { return [] }

        // Cells are read in order Début, Fin, Début, Fin … → pair them up.
        var pairs: [(start: Date, end: Date)] = []
        var i = 0
        while i + 1 < dates.count {
            let s = dates[i], e = dates[i + 1]
            if e > s { pairs.append((s, e)) }
            i += 2
        }
        if pairs.isEmpty { return [] }

        // Merge contiguous / overlapping slots into continuous duty blocks.
        pairs.sort { $0.start < $1.start }
        var merged: [DutyBlock] = []
        for p in pairs {
            if var last = merged.last, p.start <= last.end {
                if p.end > last.end { last.end = p.end }
                merged[merged.count - 1] = last
            } else {
                merged.append(DutyBlock(start: p.start, end: p.end))
            }
        }
        return merged
    }

    // MARK: - Helpers

    private static func truncatedBeforeDeletions(_ raw: String) -> String {
        let lower = raw.lowercased()
        for marker in ["supprim", "annul", "gelöscht", "storniert"] {
            if let r = lower.range(of: marker) {
                return String(raw[raw.startIndex..<r.lowerBound])
            }
        }
        return raw
    }

    /// Finds `TT-MM-JJJJ HH:MM` (also `TT.MM.JJJJ` / `TT/MM/JJJJ`) timestamps in
    /// text order. Display line-wrapping in mail apps does not affect the raw
    /// string, so a plain regex over the whole text is reliable.
    private static func dateTimes(in text: String) -> [Date] {
        let pattern = #"(\d{1,2})[-./](\d{1,2})[-./](\d{4})\s+(\d{1,2}):(\d{2})"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        var out: [Date] = []
        re.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            func g(_ i: Int) -> Int { Int(ns.substring(with: m.range(at: i))) ?? 0 }
            var c = DateComponents()
            c.day = g(1); c.month = g(2); c.year = g(3); c.hour = g(4); c.minute = g(5)
            if let d = cal.date(from: c) { out.append(d) }
        }
        return out
    }
}
