import SwiftUI

public extension Theme {
    /// A single shared transition convention, reused for every tab switch and
    /// hover-state change from D6 onward — never a per-screen reimplementation of
    /// "the transition." See CLAUDE.md, "Visual Language."
    enum Motion {
        public static let standard: Animation = .easeInOut(duration: 1.5)
    }
}

public extension View {
    /// Applies `Theme.Motion.standard` as the animation driving changes to `value`.
    func standardTransition(value: some Equatable) -> some View {
        animation(Theme.Motion.standard, value: value)
    }
}
