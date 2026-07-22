import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct ShiftEntry: TimelineEntry {
    var date: Date
    var userName: String
    var shiftName: String?
    var shiftAbbrev: String?
    var shiftTime: String?
    var shiftColor: AppColor?
    var nextTitle: String?
    var nextWhen: String?
    var conflictCount: Int

    static let placeholder = ShiftEntry(
        date: Date(), userName: "Ich",
        shiftName: "Spätdienst", shiftAbbrev: "S", shiftTime: "14:00–22:00",
        shiftColor: .indigo, nextTitle: "Abendessen mit Freunden", nextWhen: "morgen 19:00",
        conflictCount: 0)
}

// MARK: - Provider

struct ShiftProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShiftEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (ShiftEntry) -> Void) {
        completion(context.isPreview ? .placeholder : makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShiftEntry>) -> Void) {
        let entry = makeEntry()
        // Refresh at the next midnight so "today" stays correct.
        let cal = Calendar.current
        let nextMidnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    private func makeEntry() -> ShiftEntry {
        guard let data = LocalJSONPersistence().load() else {
            return ShiftEntry(date: Date(), userName: "Ich", conflictCount: 0)
        }
        let store = AppStore(readOnly: data)
        let user = store.currentUser
        let now = Date()

        var e = ShiftEntry(date: now, userName: user.name.split(separator: " ").first.map(String.init) ?? user.name,
                           conflictCount: 0)

        if let inst = store.shiftInstance(for: user.id, on: now), let t = store.shiftType(inst.shiftTypeID) {
            e.shiftName = t.name
            e.shiftAbbrev = t.abbreviation
            e.shiftTime = store.effectiveTimeString(inst)
            e.shiftColor = t.color
        }

        if let next = store.data.events
            .filter({ $0.end >= now })
            .sorted(by: { $0.start < $1.start })
            .first {
            e.nextTitle = next.title
            e.nextWhen = Self.relative(next.start)
        }

        e.conflictCount = ConflictEngine.detect(store: store, horizonDays: 14).count
        return e
    }

    private static func relative(_ date: Date) -> String {
        let cal = Calendar.current
        let tf = DateFormatter(); tf.locale = Locale(identifier: "de_DE"); tf.dateFormat = "HH:mm"
        let day: String
        if cal.isDateInToday(date) { day = "heute" }
        else if cal.isDateInTomorrow(date) { day = "morgen" }
        else { let df = DateFormatter(); df.locale = Locale(identifier: "de_DE"); df.dateFormat = "EE d.M."; day = df.string(from: date) }
        return "\(day) \(tf.string(from: date))"
    }
}

// MARK: - Views

struct ShiftLifeWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ShiftEntry

    var body: some View {
        switch family {
        case .systemSmall: small
        default: medium
        }
    }

    private var accent: Color { (entry.shiftColor ?? .slate).color }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Heute").font(.caption2).foregroundStyle(.secondary)
            if let name = entry.shiftName {
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 9, height: 9)
                    Text(name).font(.headline).lineLimit(1)
                }
                if let time = entry.shiftTime {
                    Text(time).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill").foregroundStyle(.green)
                    Text("Frei").font(.headline)
                }
            }
            Spacer(minLength: 0)
            footer
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Heute · \(entry.userName)").font(.caption2).foregroundStyle(.secondary)
                if let name = entry.shiftName {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(accent).frame(width: 10, height: 10)
                        Text(name).font(.headline).lineLimit(1)
                    }
                    if let time = entry.shiftTime {
                        Text(time).font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "sun.max.fill").foregroundStyle(.green)
                        Text("Frei heute").font(.headline)
                    }
                }
                Spacer(minLength: 0)
                footer
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text("Als Nächstes").font(.caption2).foregroundStyle(.secondary)
                if let t = entry.nextTitle {
                    Text(t).font(.subheadline).fontWeight(.medium).lineLimit(2)
                    if let w = entry.nextWhen { Text(w).font(.caption).foregroundStyle(.secondary) }
                } else {
                    Text("Nichts geplant").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder private var footer: some View {
        if entry.conflictCount > 0 {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("\(entry.conflictCount) Konflikt\(entry.conflictCount == 1 ? "" : "e")")
                    .font(.caption2).foregroundStyle(.orange)
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Keine Konflikte").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Widget

struct ShiftLifeWidget: Widget {
    let kind = "ShiftLifeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShiftProvider()) { entry in
            ShiftLifeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("ShiftLife")
        .description("Dein heutiger Dienst, der nächste Termin und offene Konflikte.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
