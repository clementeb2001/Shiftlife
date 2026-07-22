import SwiftUI
import UIKit

/// Small design system: colours, typography, spacing and reusable components.
/// Requirements honoured: modern/calm/trustworthy, Light + Dark mode, colour is
/// never the only signal (labels/icons always present), accessible font sizes.
enum Theme {
    // Brand
    static let brand = Color(red: 0.20, green: 0.48, blue: 0.90)      // ShiftLife blue
    static let brandDeep = Color(red: 0.13, green: 0.30, blue: 0.62)

    // Semantic
    static let danger = Color(red: 0.86, green: 0.30, blue: 0.30)
    static let warning = Color(red: 0.94, green: 0.56, blue: 0.20)
    static let success = Color(red: 0.20, green: 0.66, blue: 0.40)

    // Surfaces adapt automatically to light/dark via system materials.
    static var groupedBackground: Color { Color(.systemGroupedBackground) }
    static var card: Color { Color(.secondarySystemGroupedBackground) }
    static var subtleText: Color { Color(.secondaryLabel) }

    // Spacing scale (4-pt base).
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 16
        static let chip: CGFloat = 10
        static let pill: CGFloat = 100
    }
}

// MARK: - Reusable components

/// A rounded content card, the primary layout container across the app.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Space.l
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

/// A small labelled chip. Colour + text/icon so colour is never the only cue.
struct Chip: View {
    @Environment(\.colorScheme) private var scheme
    var text: String
    var systemImage: String? = nil
    var color: Color = Theme.brand
    var filled: Bool = false

    /// Readable text colour on the 15% tint background: darkened in light mode,
    /// lightened in dark mode, so even light hues stay legible.
    private var textColor: Color {
        if filled { return .white }
        return Chip.readable(color, scheme)
    }

    static func readable(_ color: Color, _ scheme: ColorScheme) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        if scheme == .dark {
            return Color(red: r * 0.55 + 0.45, green: g * 0.55 + 0.45, blue: b * 0.55 + 0.45)
        }
        return Color(red: r * 0.6, green: g * 0.6, blue: b * 0.6)
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.caption2) }
            Text(text).font(.caption).fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(textColor)
        .background(filled ? color : color.opacity(0.15))
        .clipShape(Capsule())
    }
}

/// Section header used above cards.
struct SectionHeader: View {
    var title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).foregroundStyle(Theme.brand) }
            Text(title).font(.headline)
            Spacer()
        }
    }
}

/// Coloured member avatar with initials (works without colour perception too).
struct MemberAvatar: View {
    var member: HouseholdMember
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(member.color.color)
            Text(member.initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if member.role == .child {
                Image(systemName: "figure.child")
                    .font(.system(size: size * 0.28))
                    .padding(2)
                    .background(Circle().fill(Theme.card))
                    .foregroundStyle(member.color.color)
            }
        }
        .accessibilityLabel(Text("\(member.name), \(member.role.label)"))
    }
}

/// Empty-state placeholder.
struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(Theme.brand.opacity(0.7))
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.subtleText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.xl)
    }
}

// MARK: - Formatting helpers

enum Format {
    static let de = Locale(identifier: "de_DE")

    static func time(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = de; f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
    static func weekdayShort(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = de; f.dateFormat = "EE"
        return f.string(from: date)
    }
    static func dayMonth(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = de; f.dateFormat = "d. MMM"
        return f.string(from: date)
    }
    static func full(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = de; f.dateFormat = "EEEE, d. MMMM"
        return f.string(from: date)
    }
    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Heute" }
        if cal.isDateInTomorrow(date) { return "Morgen" }
        let f = DateFormatter(); f.locale = de; f.dateFormat = "EE, d. MMM"
        return f.string(from: date)
    }
    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h) Std \(m) Min" }
        if h > 0 { return "\(h) Std" }
        return "\(m) Min"
    }
    static func windowLabel(_ w: AvailabilityWindow) -> String {
        "\(relativeDay(w.start)) · \(time(w.start))–\(time(w.end))"
    }
}
