import Foundation
import SwiftUI

// MARK: - Color helpers

/// Named palette so we never persist raw Color (which isn't Codable) and colours
/// stay consistent across light/dark mode. Colour is never the ONLY information
/// carrier in the UI (see design requirement) – it always pairs with a label/icon.
/// One shared 16-colour palette for both shift types and people, so a shift
/// colour never has to collide with a person's colour.
enum AppColor: String, Codable, CaseIterable, Identifiable {
    case blue, navy, indigo, purple, magenta, pink, rose, red
    case orange, amber, brown, green, lime, teal, cyan, slate
    // Legacy values kept so previously stored data still decodes.
    case gray

    var id: String { rawValue }

    /// Base RGB (0…1) for the colour.
    var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .blue:    return (0.204, 0.471, 0.902)
        case .navy:    return (0.169, 0.294, 0.561)
        case .indigo:  return (0.322, 0.353, 0.780)
        case .purple:  return (0.549, 0.361, 0.820)
        case .magenta: return (0.722, 0.302, 0.769)
        case .pink:    return (0.898, 0.345, 0.624)
        case .rose:    return (0.878, 0.439, 0.541)
        case .red:     return (0.878, 0.333, 0.357)
        case .orange:  return (0.937, 0.561, 0.200)
        case .amber:   return (0.878, 0.663, 0.231)
        case .brown:   return (0.608, 0.420, 0.290)
        case .green:   return (0.184, 0.627, 0.376)
        case .lime:    return (0.482, 0.718, 0.286)
        case .teal:    return (0.122, 0.631, 0.620)
        case .cyan:    return (0.125, 0.682, 0.753)
        case .slate:   return (0.392, 0.439, 0.537)
        case .gray:    return (0.500, 0.530, 0.580)
        }
    }

    var color: Color { Color(red: rgb.r, green: rgb.g, blue: rgb.b) }

    /// A readable text colour for this hue on a light tint of itself, adapting
    /// to the theme: darkened in light mode, lightened in dark mode. Keeps even
    /// light hues (lime, amber, cyan) legible on the tinted pill background.
    func readableText(_ scheme: ColorScheme) -> Color {
        let c = rgb
        if scheme == .dark {
            return Color(red: c.r * 0.55 + 0.45, green: c.g * 0.55 + 0.45, blue: c.b * 0.55 + 0.45)
        } else {
            return Color(red: c.r * 0.60, green: c.g * 0.60, blue: c.b * 0.60)
        }
    }

    var label: String {
        switch self {
        case .blue: return "Blau"
        case .navy: return "Navy"
        case .indigo: return "Indigo"
        case .purple: return "Violett"
        case .magenta: return "Magenta"
        case .pink: return "Rosa"
        case .rose: return "Altrosa"
        case .red: return "Rot"
        case .orange: return "Orange"
        case .amber: return "Bernstein"
        case .brown: return "Braun"
        case .green: return "Grün"
        case .lime: return "Limette"
        case .teal: return "Türkis"
        case .cyan: return "Cyan"
        case .slate: return "Schiefer"
        case .gray: return "Grau"
        }
    }

    /// Colours offered in pickers (legacy `.gray` hidden but still decodable).
    static var pickable: [AppColor] { allCases.filter { $0 != .gray } }
}

// MARK: - Household & members

enum MemberRole: String, Codable, CaseIterable, Identifiable {
    case shiftWorker   // Schichtarbeiter:in
    case partner       // Partner:in
    case child         // Kind (kein eigenes Konto)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shiftWorker: return "Schichtarbeiter:in"
        case .partner: return "Partner:in"
        case .child: return "Kind"
        }
    }

    var systemImage: String {
        switch self {
        case .shiftWorker: return "briefcase.fill"
        case .partner: return "heart.fill"
        case .child: return "figure.child"
        }
    }
}

/// Visibility levels for events/tasks as required by the concept:
/// only me, partner, selected members or whole household.
enum Visibility: String, Codable, CaseIterable, Identifiable {
    case privateOnly   // nur ich
    case partner       // Partner
    case household     // gesamter Haushalt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .privateOnly: return "Nur ich"
        case .partner: return "Partner"
        case .household: return "Ganzer Haushalt"
        }
    }

    var systemImage: String {
        switch self {
        case .privateOnly: return "lock.fill"
        case .partner: return "person.2.fill"
        case .household: return "house.fill"
        }
    }
}

struct HouseholdMember: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var role: MemberRole
    var color: AppColor
    /// The device owner. Exactly one member is the current user in this local MVP.
    var isCurrentUser: Bool = false
    /// For children: school / day-care description (V1.5 child profile).
    var careInfo: String = ""
    /// For children: recurring pickup slots used for childcare planning.
    var pickups: [Pickup] = []
    /// For children: birth year, used to derive age.
    var birthYear: Int? = nil
    /// For children: age up to which adult supervision applies. Above it the
    /// child is considered independent and plans on their own.
    var supervisionUntilAge: Int = 12

    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    /// Approximate current age in years (nil if no birth year set).
    func age(now: Date = Date()) -> Int? {
        birthYear.map { Calendar.current.component(.year, from: now) - $0 }
    }

    /// Does this child still need adult supervision for its activities?
    var needsSupervisionByAge: Bool {
        guard role == .child else { return false }
        guard let a = age() else { return true }   // unknown age → assume yes
        return a <= supervisionUntilAge
    }
}

/// A recurring pickup / care slot for a child (V1.5 Abholplanung).
struct Pickup: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// Calendar weekday: 1 = Sunday … 7 = Saturday (matches `Calendar.component(.weekday)`).
    var weekday: Int
    /// Minutes from midnight.
    var startMinutes: Int
    /// Default responsible adult, or nil = still open (raises a conflict).
    var responsibleID: UUID? = nil
    var label: String = "Abholung"

    var timeString: String { ShiftType.timeString(startMinutes) }
}

struct Household: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    /// Human friendly invite code shown in the app (local MVP – no real server).
    var inviteCode: String
}

// MARK: - Shifts

/// A type of duty: Früh, Spät, Nacht, Bereitschaft … with time window and colour.
struct ShiftType: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var abbreviation: String          // Schichtkürzel, z. B. "F", "S", "N"
    var color: AppColor
    /// Minutes from midnight for start/end. If end <= start the shift crosses midnight.
    var startMinutes: Int
    var endMinutes: Int
    /// Optional rest period (Ruhezeit) in hours to block AFTER the shift ends,
    /// e.g. recovery after a night shift.
    var restHours: Int = 0
    /// When true, the start/end here are only a default; the actual time span is
    /// entered individually each time the shift is added (e.g. volunteer fire
    /// brigade on-call). The per-day times live on the ShiftInstance.
    var hasVariableTime: Bool = false
    /// A shift can represent "off" categories (Urlaub/Krankheit) that don't block
    /// common free time in the same way. `blocksTime == false` means the person is
    /// simply unavailable-labelled but still counts as free for planning.
    var counterCategory: ShiftCategory = .work

    var startTimeString: String { Self.timeString(startMinutes) }
    var endTimeString: String { Self.timeString(endMinutes) }

    var crossesMidnight: Bool { endMinutes <= startMinutes }

    static func timeString(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}

enum ShiftCategory: String, Codable, CaseIterable, Identifiable {
    case work        // reguläre Schicht – blockiert Zeit
    case onCall      // Bereitschaft / Rufbereitschaft – blockiert Zeit
    case training    // Fortbildung – blockiert Zeit
    case vacation    // Urlaub – frei
    case sick        // Krankheit – frei
    case overtime    // Überstunden – blockiert Zeit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .work: return "Schicht"
        case .onCall: return "Bereitschaft"
        case .training: return "Fortbildung"
        case .vacation: return "Urlaub"
        case .sick: return "Krankheit"
        case .overtime: return "Überstunden"
        }
    }

    /// Does the duty block the person's time for common-free-time detection?
    var blocksTime: Bool {
        switch self {
        case .work, .onCall, .training, .overtime: return true
        case .vacation, .sick: return false
        }
    }
}

/// A recurring pattern, e.g. Früh-Früh-Spät-Spät-Nacht-Nacht-Frei.
/// Each entry references a ShiftType id, or nil for a free day.
struct ShiftPattern: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// Ordered cycle. `nil` = Frei (day off).
    var sequence: [UUID?]

    var lengthInDays: Int { sequence.count }
}

/// A concrete shift on a concrete date for a member. Created either by applying a
/// pattern or added/edited manually. Editing a single instance never destroys the
/// underlying pattern (see MVP requirement 6).
struct ShiftInstance: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var memberID: UUID
    var shiftTypeID: UUID
    /// Calendar day (normalised to start of day).
    var date: Date
    /// True when this instance was hand-edited and should survive pattern re-apply.
    var isManualOverride: Bool = false
    /// Individual start/end (minutes from midnight) for variable-time shifts;
    /// nil falls back to the shift type's default times.
    var startMinutesOverride: Int? = nil
    var endMinutesOverride: Int? = nil
}

// MARK: - Calendar events & tasks

enum EventCategory: String, Codable, CaseIterable, Identifiable {
    case personal      // privat
    case shared        // gemeinsam
    case childcare     // Betreuung / Abholung
    case appointment   // Termin (Arzt etc.)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .personal: return "Privat"
        case .shared: return "Gemeinsam"
        case .childcare: return "Betreuung"
        case .appointment: return "Termin"
        }
    }

    var systemImage: String {
        switch self {
        case .personal: return "person.fill"
        case .shared: return "person.2.fill"
        case .childcare: return "figure.and.child.holdinghands"
        case .appointment: return "calendar"
        }
    }
}

/// For events involving a child: how much adult supervision they need.
enum ChildSupervision: String, Codable, CaseIterable, Identifiable {
    case parentRequired  // ein Elternteil muss dabei sein
    case noParent        // kein Elternteil nötig
    case informational   // legacy (== noParent), kept so old data still decodes

    var id: String { rawValue }
    var label: String {
        switch self {
        case .parentRequired: return "Ein Elternteil muss dabei sein"
        case .noParent, .informational: return "Kein Elternteil nötig"
        }
    }
    var hint: String {
        switch self {
        case .parentRequired: return "Konflikt nur, wenn kein Elternteil kann."
        case .noParent, .informational: return "Kein Konflikt."
        }
    }
    /// Map legacy `.informational` onto `.noParent`.
    var normalized: ChildSupervision { self == .informational ? .noParent : self }
    /// Options offered in the picker (legacy value hidden).
    static var pickable: [ChildSupervision] { [.parentRequired, .noParent] }
}

struct CalendarEvent: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var start: Date
    var end: Date
    var category: EventCategory
    var visibility: Visibility
    /// Members this event involves. A childcare event that involves a child needs a
    /// responsible adult; if none is available a conflict is raised.
    var memberIDs: [UUID]
    /// Optional responsible person for a childcare/pickup event.
    var responsibleMemberID: UUID? = nil
    var notes: String = ""
    /// Optional explicit calendar colour. When nil the colour is derived from the
    /// associated person (child → partner → me).
    var colorOverride: AppColor? = nil
    /// For events that involve a child: how much adult supervision is required.
    var childSupervision: ChildSupervision? = nil
    /// True when auto-generated from a child's recurring pickup schedule.
    var isGenerated: Bool = false
    /// The child this generated event belongs to (for clean regeneration).
    var sourceChildID: UUID? = nil
}

enum TaskCondition: String, Codable, CaseIterable, Identifiable {
    case none
    case nextFreeDay        // am nächsten freien Tag
    case beforeLateShift    // vor dem Spätdienst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Keine Bedingung"
        case .nextFreeDay: return "Am nächsten freien Tag"
        case .beforeLateShift: return "Vor dem nächsten Spätdienst"
        }
    }
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
    /// nil = assigned to the whole household.
    var assigneeID: UUID? = nil
    var dueDate: Date? = nil
    var condition: TaskCondition = .none
    var visibility: Visibility = .household
    var repeats: Bool = false
}

// MARK: - Derived / computed types (not persisted)

/// A window of time in which selected members are all free and rested.
struct AvailabilityWindow: Identifiable, Hashable {
    var id = UUID()
    var start: Date
    var end: Date
    var memberIDs: [UUID]

    var durationMinutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

enum ConflictSeverity: Int, Codable, Comparable {
    case low = 0, medium = 1, high = 2
    static func < (lhs: ConflictSeverity, rhs: ConflictSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    var label: String {
        switch self {
        case .high: return "Hoch"
        case .medium: return "Mittel"
        case .low: return "Niedrig"
        }
    }
    var color: AppColor {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .gray
        }
    }
}

enum ConflictKind: Codable, Hashable {
    case eventDuringShift        // Termin kollidiert mit Schicht
    case bothParentsWorking      // beide Eltern arbeiten während Betreuung
    case eventAfterNightShift    // Termin direkt nach Nachtschicht
    case unassignedTask          // Aufgabe ohne verfügbare Person
    case childcareUncovered      // Betreuungsfenster ohne verantwortliche Person
}

/// A detected conflict with a concrete, actionable description.
struct Conflict: Identifiable, Hashable {
    var id = UUID()
    var kind: ConflictKind
    var severity: ConflictSeverity
    var title: String
    var detail: String
    var date: Date
    /// Optional linked entities so the UI can offer targeted actions.
    var eventID: UUID? = nil
    var taskID: UUID? = nil
    var memberIDs: [UUID] = []
}
