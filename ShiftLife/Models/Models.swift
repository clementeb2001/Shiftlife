import Foundation
import SwiftUI

// MARK: - Color helpers

/// Named palette so we never persist raw Color (which isn't Codable) and colours
/// stay consistent across light/dark mode. Colour is never the ONLY information
/// carrier in the UI (see design requirement) – it always pairs with a label/icon.
enum AppColor: String, Codable, CaseIterable, Identifiable {
    case blue, teal, green, orange, red, purple, pink, indigo, brown, gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue:   return Color(red: 0.20, green: 0.48, blue: 0.90)
        case .teal:   return Color(red: 0.13, green: 0.63, blue: 0.62)
        case .green:  return Color(red: 0.20, green: 0.66, blue: 0.40)
        case .orange: return Color(red: 0.94, green: 0.56, blue: 0.20)
        case .red:    return Color(red: 0.86, green: 0.30, blue: 0.30)
        case .purple: return Color(red: 0.55, green: 0.36, blue: 0.82)
        case .pink:   return Color(red: 0.90, green: 0.40, blue: 0.62)
        case .indigo: return Color(red: 0.32, green: 0.35, blue: 0.78)
        case .brown:  return Color(red: 0.55, green: 0.44, blue: 0.33)
        case .gray:   return Color(red: 0.50, green: 0.53, blue: 0.58)
        }
    }

    var label: String {
        switch self {
        case .blue: return "Blau"
        case .teal: return "Türkis"
        case .green: return "Grün"
        case .orange: return "Orange"
        case .red: return "Rot"
        case .purple: return "Violett"
        case .pink: return "Rosa"
        case .indigo: return "Indigo"
        case .brown: return "Braun"
        case .gray: return "Grau"
        }
    }
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

    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
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
