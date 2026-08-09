import SwiftUI

public extension Theme {
    /// Spacing scale — views reference these tokens, never magic numbers, per
    /// CLAUDE.md's Design System rule.
    enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
    }

    /// Window/layout sizing constants. `defaultWindowSize`'s only consumer as of
    /// D5 is `ROADMAP.md` D6/T6.1's `AutoCueApp.swift` scene declaration — defined
    /// here now so that Deliverable references a token instead of a hardcoded
    /// magic number.
    enum Layout {
        /// Default/initial Project window size. Layout is responsive to resizing
        /// where feasible — this is not a fixed constraint.
        public static let defaultWindowSize = CGSize(width: 1290, height: 800)
    }
}
