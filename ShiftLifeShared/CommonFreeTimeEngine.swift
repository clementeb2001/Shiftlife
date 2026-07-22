import Foundation

/// Filters for a common-free-time search (see "Gemeinsame Zeit" view).
struct FreeTimeQuery {
    var memberIDs: [UUID]
    var rangeStart: Date
    var rangeEnd: Date
    var minimumDurationMinutes: Int = 60
    /// Optional time-of-day window (minutes from midnight) both start & end must fall in.
    var earliestMinute: Int = 0        // e.g. only evenings -> 17*60
    var latestMinute: Int = 24 * 60
}

/// Detects windows where ALL selected members are simultaneously free (and rested).
///
/// Algorithm (documented so it is auditable, per the concept's "nachvollziehbare Logik"):
/// 1. For every selected member collect busy intervals (shifts + rest + events).
/// 2. Merge everyone's busy intervals into one combined busy timeline.
/// 3. The gaps between combined busy intervals within the range are candidate free windows.
/// 4. Clip each gap to the requested time-of-day window, split across days if needed.
/// 5. Keep windows that meet the minimum duration. Sort ascending by start.
enum CommonFreeTimeEngine {

    static func freeWindows(store: AppStore, query: FreeTimeQuery) -> [AvailabilityWindow] {
        guard !query.memberIDs.isEmpty else { return [] }

        // 1 + 2: combined busy timeline.
        var busy: [(start: Date, end: Date)] = []
        for id in query.memberIDs {
            for b in store.busyIntervals(for: id, from: query.rangeStart, to: query.rangeEnd) {
                busy.append((max(b.start, query.rangeStart), min(b.end, query.rangeEnd)))
            }
        }
        let merged = mergeIntervals(busy)

        // 3: gaps = free windows.
        var gaps: [(Date, Date)] = []
        var cursor = query.rangeStart
        for b in merged {
            if b.start > cursor {
                gaps.append((cursor, b.start))
            }
            cursor = max(cursor, b.end)
        }
        if cursor < query.rangeEnd {
            gaps.append((cursor, query.rangeEnd))
        }

        // 4 + 5: clip to time-of-day window per day and apply duration filter.
        let cal = Calendar.current
        var windows: [AvailabilityWindow] = []
        for gap in gaps {
            for clipped in clipToDaily(start: gap.0, end: gap.1,
                                       earliest: query.earliestMinute,
                                       latest: query.latestMinute,
                                       calendar: cal) {
                let minutes = Int(clipped.1.timeIntervalSince(clipped.0) / 60)
                if minutes >= query.minimumDurationMinutes {
                    windows.append(AvailabilityWindow(start: clipped.0, end: clipped.1,
                                                      memberIDs: query.memberIDs))
                }
            }
        }
        return windows.sorted { $0.start < $1.start }
    }

    /// The very next common free window of at least `minimumDurationMinutes`.
    static func nextWindow(store: AppStore, memberIDs: [UUID],
                           minimumDurationMinutes: Int = 60,
                           horizonDays: Int = 21) -> AvailabilityWindow? {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: horizonDays, to: now)!
        let q = FreeTimeQuery(memberIDs: memberIDs, rangeStart: now, rangeEnd: end,
                              minimumDurationMinutes: minimumDurationMinutes)
        return freeWindows(store: store, query: q).first
    }

    /// Next common free EVENING (>= 2h between 17:00 and 23:00).
    static func nextEvening(store: AppStore, memberIDs: [UUID], horizonDays: Int = 21) -> AvailabilityWindow? {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: horizonDays, to: now)!
        let q = FreeTimeQuery(memberIDs: memberIDs, rangeStart: now, rangeEnd: end,
                              minimumDurationMinutes: 120,
                              earliestMinute: 17 * 60, latestMinute: 23 * 60)
        return freeWindows(store: store, query: q).first
    }

    /// Count of common free full days in a month (no busy interval that whole day).
    static func freeDaysInMonth(store: AppStore, memberIDs: [UUID], monthAnchor: Date) -> [Date] {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: monthAnchor),
              let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: monthAnchor))
        else { return [] }

        var freeDays: [Date] = []
        for dayNum in range {
            guard let day = cal.date(byAdding: .day, value: dayNum - 1, to: monthStart) else { continue }
            let dayStart = cal.startOfDay(for: day)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
            var anyBusy = false
            for id in memberIDs {
                if !store.busyIntervals(for: id, from: dayStart, to: dayEnd).isEmpty {
                    anyBusy = true
                    break
                }
            }
            if !anyBusy { freeDays.append(dayStart) }
        }
        return freeDays
    }

    // MARK: - Helpers

    static func mergeIntervals(_ intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        let sorted = intervals.filter { $0.start < $0.end }.sorted { $0.start < $1.start }
        var merged: [(start: Date, end: Date)] = []
        for iv in sorted {
            if var last = merged.last, iv.start <= last.end {
                last.end = max(last.end, iv.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(iv)
            }
        }
        return merged
    }

    /// Splits a multi-day window into per-day slices clipped to [earliest, latest] minutes.
    private static func clipToDaily(start: Date, end: Date, earliest: Int, latest: Int,
                                    calendar cal: Calendar) -> [(Date, Date)] {
        guard start < end else { return [] }
        // Fast path: full-day window not restricted.
        if earliest == 0 && latest >= 24 * 60 {
            return [(start, end)]
        }
        var result: [(Date, Date)] = []
        var day = cal.startOfDay(for: start)
        let lastDay = cal.startOfDay(for: end)
        while day <= lastDay {
            let windowStart = cal.date(byAdding: .minute, value: earliest, to: day)!
            let windowEnd = cal.date(byAdding: .minute, value: latest, to: day)!
            let s = max(start, windowStart)
            let e = min(end, windowEnd)
            if s < e { result.append((s, e)) }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }
}
