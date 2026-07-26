import Foundation

/// Adaptive routine: a task anchored relative to a shift (before start / after
/// end). Moves automatically when the shift moves.
struct ShiftRoutine: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var label: String
    var offsetMinutes: Int          // distance from the anchor
    var afterShift: Bool = false    // false = before start, true = after end
}

/// A category for Life-Window activity suggestions.
struct ActivityCategory: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var emoji: String
    var label: String
    var minMinutes: Int             // shortest window it fits into
}

/// How suitable a free window is, given recovery after demanding shifts.
enum RecoveryLevel {
    case ideal, possible, unfavorable

    var label: String {
        switch self {
        case .ideal: return "ideal"
        case .possible: return "möglich"
        case .unfavorable: return "ungünstig"
        }
    }
    var emoji: String {
        switch self {
        case .ideal: return "✅"
        case .possible: return "🟡"
        case .unfavorable: return "😴"
        }
    }
    /// Colour name from the shared palette (AppColor).
    var appColor: AppColor {
        switch self {
        case .ideal: return .green
        case .possible: return .amber
        case .unfavorable: return .red
        }
    }
}
