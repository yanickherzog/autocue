import SwiftUI

/// Enforces CLAUDE.md's "sharp corners — no rounded corners anywhere, ever" rule as
/// a real, reusable component. SwiftUI's stock `.bordered`/`.borderedProminent`
/// button styles round corners by default on macOS, so a plain `Button` with no
/// explicit style would silently violate the rule — this style exists specifically
/// so no future button call site has to remember "don't add `.cornerRadius()`."
public struct SharpButtonStyle: ButtonStyle {
    public enum Emphasis: Equatable {
        case primary
        case secondary
    }

    private let emphasis: Emphasis
    private let surface: Theme.Surface

    public init(emphasis: Emphasis = .primary, surface: Theme.Surface = .primary) {
        self.emphasis = emphasis
        self.surface = surface
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.font(.medium, size: 13))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .overlay(
                Rectangle()
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            // Without this, SwiftUI hit-tests only the label's own drawn
            // content (e.g. a Text's tight glyph bounds), not the padded/
            // backgrounded rectangle this style visually draws — a real
            // usability bug (clickable only on the text itself), not a
            // hypothetical: found during D6's manual verification on a
            // full-width sidebar button, where the dead space was large
            // enough to notice. Fixed here, once, for every button using
            // this style, rather than patched per call site.
            .contentShape(Rectangle())
        // Deliberately no `.clipShape`/`.cornerRadius` call — a plain `Rectangle`
        // background/overlay is square by construction.
    }

    private var foregroundColor: Color {
        switch emphasis {
        case .primary: surface.background
        case .secondary: surface.foreground
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch emphasis {
        case .primary: Theme.Colors.accent.opacity(isPressed ? 0.8 : 1)
        case .secondary: surface.foreground.opacity(isPressed ? 0.1 : 0)
        }
    }

    private var borderColor: Color {
        switch emphasis {
        case .primary: .clear
        case .secondary: surface.foreground.opacity(0.3)
        }
    }
}

#Preview("SharpButtonStyle") {
    HStack(spacing: Theme.Spacing.md) {
        Button("Primary") {}
            .buttonStyle(SharpButtonStyle(emphasis: .primary, surface: .primary))
        Button("Secondary") {}
            .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
    }
    .padding(Theme.Spacing.lg)
    .background(Theme.Surface.primary.background)
}
