import SwiftUI

/// Central design tokens. Warm, minimal, mobile-first.
/// Cream background, amber accent, monospaced numerals for stats.
enum Theme {
    static let cream = Color(hex: 0xFAF7F2)
    static let amber = Color(hex: 0xC45621)
    static let ink = Color(hex: 0x2B2320)
    static let inkSoft = Color(hex: 0x6B615A)
    static let card = Color(hex: 0xFFFFFF)
    static let hairline = Color(hex: 0xE7E0D8)
    static let good = Color(hex: 0x3F7D5B)
    static let warn = Color(hex: 0xB5892B)

    /// Monospaced face for numbers and stats.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

/// A plain card container used across screens.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }
}

/// A prominent amber button for primary actions.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.amber.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A small pill label used for tags / flags.
struct Pill: View {
    let text: String
    var color: Color = Theme.amber
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

/// A labelled numeric stat rendered in monospace.
struct Stat: View {
    let value: String
    let label: String
    var sample: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.mono(20, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(label).font(.caption).foregroundStyle(Theme.inkSoft)
            if let sample {
                Text(sample).font(Theme.mono(11)).foregroundStyle(Theme.inkSoft)
            }
        }
    }
}
