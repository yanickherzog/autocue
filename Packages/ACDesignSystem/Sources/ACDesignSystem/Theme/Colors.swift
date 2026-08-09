import SwiftUI

/// Root namespace for AutoCue's design tokens — colors, typography, spacing, motion.
/// See CLAUDE.md, "Design System" → "Visual Language," for the source design brief
/// these tokens implement.
public enum Theme {}

public extension Theme {
    /// AutoCue's fixed brand palette. These do not adapt to the system Light/Dark
    /// Mode setting — see docs/DECISIONS.md, "AutoCue does not adapt to system
    /// Light/Dark Mode," for why.
    enum Colors {
        public static let carbonBlack = Color(red: 0x20 / 255, green: 0x20 / 255, blue: 0x20 / 255)
        public static let white = Color(red: 1, green: 1, blue: 1)
        public static let accent = Color(red: 0x93 / 255, green: 0x03 / 255, blue: 0x2E / 255)

        /// Ghost/placeholder text on the primary surface — Carbon Black at 40% opacity.
        /// No reversed-surface equivalent yet; add one only when a real input field on
        /// a reversed-surface screen actually needs it, not speculatively.
        public static let ghostTextPrimary = carbonBlack.opacity(0.4)
    }

    /// Two fixed surface styles, selected per screen — Setup/Cue Sheet use
    /// `.primary`, Review & Export uses `.reversed`. Never driven by
    /// `colorScheme`; both cases resolve to the same values regardless of the
    /// system appearance setting. A sibling of `Colors`, not nested inside it,
    /// to keep type nesting at most 1 level deep (SwiftLint's `nesting` rule).
    enum Surface: Equatable {
        case primary
        case reversed

        public var background: Color {
            switch self {
            case .primary: Colors.white
            case .reversed: Colors.carbonBlack
            }
        }

        public var foreground: Color {
            switch self {
            case .primary: Colors.carbonBlack
            case .reversed: Colors.white
            }
        }
    }
}
